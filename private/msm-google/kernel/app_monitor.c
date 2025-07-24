/*
 * Android Application Monitor
 * 动态监控指定Android应用的系统调用行为
 */
 

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/mutex.h>
#include <linux/string.h>
#include <linux/jiffies.h>
#include <linux/sched.h>
#include <linux/cred.h>


#define CONFIG_FILE_PATH "/data/local/tmp/monitor_apps.txt"
#define MAX_APP_NAMES 20
#define MAX_APP_NAME_LEN 64


// 全局变量
static char target_apps[MAX_APP_NAMES][MAX_APP_NAME_LEN];
static int target_app_count = 0;
static DEFINE_MUTEX(config_mutex);
static unsigned long last_config_check = 0;
static unsigned long config_check_interval = HZ * 10; // 10秒检查一次

//进程监控变量
#define MAX_MONITORED_PIDS 80
static pid_t monitored_pids[MAX_MONITORED_PIDS];
static int monitored_count = 0;
static DEFINE_SPINLOCK(monitor_lock);


// 函数声明
static int load_target_apps(void);
static void check_config_update(void);
static bool is_target_app(const char *main_comm,const char *comm);



/**
 * 添加进程组到监控列表
 * @main_pid: 主进程的PID，也是整个进程组的TGID
 * 
 * 注意：在Linux中，线程组的所有线程共享同一个TGID
 * TGID = 主线程的PID = 进程组标识符
 */
void app_monitor_add_process_group(pid_t main_pid)
{
    unsigned long flags;
    int i;
    
    spin_lock_irqsave(&monitor_lock, flags);
    
    // 检查是否已经在监控列表中，避免重复添加
    for (i = 0; i < monitored_count; i++) {
        if (monitored_pids[i] == main_pid) {
            spin_unlock_irqrestore(&monitor_lock, flags);
            printk(KERN_DEBUG "APP_MONITOR: Process group TGID=%d already monitored\n", main_pid);
            return;
        }
    }
    
    // 添加新的进程组到监控列表
    if (monitored_count < MAX_MONITORED_PIDS) {
        monitored_pids[monitored_count] = main_pid;
        monitored_count++;
        printk(KERN_INFO "APP_MONITOR: Added process group TGID=%d (total: %d)\n", 
               main_pid, monitored_count);
    } 
    // else {
    //     printk(KERN_WARNING "APP_MONITOR: Monitor list full, cannot add TGID=%d\n", main_pid);
    // }
    
    spin_unlock_irqrestore(&monitor_lock, flags);
}

/**
 * 检查当前进程/线程是否在监控列表中
 * 通过比较当前线程的TGID来判断整个进程组是否被监控
 * 
 * 工作原理：
 * - 主进程：PID == TGID，直接匹配
 * - 子线程：PID != TGID，通过TGID匹配到主进程
 * 
 * @return: true-该进程组在监控中，false-不在监控中
 */
bool app_monitor_is_monitored_process_group(void)
{
    unsigned long flags;
    bool found = false;
    int i;
    pid_t current_tgid = current->tgid;  // 获取当前线程的线程组ID
    
    // 如果监控列表为空，直接返回false，避免无谓的锁操作
    if (monitored_count == 0) {
        return false;
    }
    
    spin_lock_irqsave(&monitor_lock, flags);
    
    // 遍历监控列表，查找当前线程组ID
    for (i = 0; i < monitored_count; i++) {
        if (monitored_pids[i] == current_tgid) {
            found = true;
            break;
        }
    }
    
    spin_unlock_irqrestore(&monitor_lock, flags);
    
    return found;
}

/**
 * 从监控列表中移除进程组
 * @main_pid: 要移除的进程组TGID
 * 
 * 通常在主进程退出时调用，清理监控列表
 */
void app_monitor_remove_process_group(pid_t main_pid)
{
    unsigned long flags;
    int i, j;
    
    spin_lock_irqsave(&monitor_lock, flags);
    
    // 查找要删除的进程组
    for (i = 0; i < monitored_count; i++) {
        if (monitored_pids[i] == main_pid) {
            // 将后续元素前移，填补空缺
            for (j = i; j < monitored_count - 1; j++) {
                monitored_pids[j] = monitored_pids[j + 1];
            }
            monitored_count--;
            printk(KERN_INFO "APP_MONITOR: Removed process group TGID=%d (total: %d)\n", 
                   main_pid, monitored_count);
            break;
        }
    }
    
    spin_unlock_irqrestore(&monitor_lock, flags);
}

// 导出符号供其他内核模块使用
EXPORT_SYMBOL(app_monitor_add_process_group);
EXPORT_SYMBOL(app_monitor_is_monitored_process_group);
EXPORT_SYMBOL(app_monitor_remove_process_group);



// 读取配置文件
static int load_target_apps(void)
{
    struct file *file;
    char *buffer;
    loff_t pos = 0;
    ssize_t bytes_read;
    char *line, *next_line;
    int count = 0;
    
    file = filp_open(CONFIG_FILE_PATH, O_RDONLY, 0);
    if (IS_ERR(file)) {
        // 如果文件不存在，使用默认配置
        if (target_app_count == 0) {
            strcpy(target_apps[0], "cn.damai");
            target_app_count = 1;
            printk(KERN_INFO "hhhAPP_MONITOR: using default app 'cn.damai'\n");
        }
        return -ENOENT;
    }
    
    buffer = kmalloc(PAGE_SIZE, GFP_KERNEL);
    if (!buffer) {
        filp_close(file, NULL);
        return -ENOMEM;
    }
    
    // 改为这个：
    bytes_read = kernel_read(file, pos, buffer, PAGE_SIZE - 1);
    pos += bytes_read;  // 手动更新位置

    filp_close(file, NULL);
    
    if (bytes_read <= 0) {
        kfree(buffer);
        return -EIO;
    }
    
    buffer[bytes_read] = '\0';
    
    // 解析配置文件，每行一个应用名
    mutex_lock(&config_mutex);
    target_app_count = 0;
    
    line = buffer;
    while (line && count < MAX_APP_NAMES) {
        next_line = strchr(line, '\n');
        if (next_line) {
            *next_line = '\0';
            next_line++;
        }
        
        // 去除空白字符
        while (*line == ' ' || *line == '\t') line++;
        
        // 跳过空行和注释行
        if (*line != '\0' && *line != '#') {
            int len = strlen(line);
            // 去除行尾空白
            while (len > 0 && (line[len-1] == ' ' || line[len-1] == '\t' || 
                              line[len-1] == '\r')) {
                line[--len] = '\0';
            }
            
            if (len > 0 && len < MAX_APP_NAME_LEN) {
                strcpy(target_apps[count], line);
                count++;
                printk(KERN_INFO "hhhAPP_MONITOR: loaded app '%s'\n", line);
            }
        }
        
        line = next_line;
    }
    
    target_app_count = count;
    mutex_unlock(&config_mutex);
    
    kfree(buffer);
    printk(KERN_INFO "hhhAPP_MONITOR: loaded %d apps from config file\n", count);
    return 0;
}




// 检查是否需要重新加载配置
static void check_config_update(void)
{
    if (time_after(jiffies, last_config_check + config_check_interval)) {
        last_config_check = jiffies;
        load_target_apps();
    }
}


// 检查是否是目标应用
static bool is_target_app(const char *main_comm,const char *comm)
{
    int i;
    bool found = false;
    
    // 定期检查配置文件更新
    check_config_update();
    
    mutex_lock(&config_mutex);
    for (i = 0; i < target_app_count; i++) {

        // 打印每次比较的详情
       // printk(KERN_DEBUG "hhhh APP_MONITOR: nowapp:'%s' with target[%d]='%s'\n", comm, i, target_apps[i]);

        if (strcmp("main",main_comm) == 0 && strstr(target_apps[i], comm) != NULL) {
            found = true;
            break;
        }
    }
    mutex_unlock(&config_mutex);
    
    return found;
}

// 供外部调用的接口函数
bool app_monitor_is_target(const char *main_comm,const char *comm)
{
    return is_target_app(main_comm,comm);
}
EXPORT_SYMBOL(app_monitor_is_target);


// 內核子系統初始化
static int __init app_monitor_init(void)
{
    int ret;
    
    printk(KERN_INFO "APP_MONITOR: initializing Android app monitor system\n");
    
    // 初始加载配置
    ret = load_target_apps();
    if (ret < 0) {
        printk(KERN_WARNING "APP_MONITOR: failed to load config, using defaults\n");
    }
    
    return 0;
}

// 使用内核初始化宏
subsys_initcall(app_monitor_init);