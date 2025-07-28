#ifndef _LINUX_APP_MONITOR_H
#define _LINUX_APP_MONITOR_H

// 检查指定的应用名是否是监控目标
bool app_monitor_is_target(const char *main_comm,const char *comm);


// 检查是否启用了全局监控
//bool app_monitor_is_enabled_all(void);

// 新增：进程组监控函数
void app_monitor_add_process_group(pid_t main_pid);
bool app_monitor_is_monitored_process_group(void);
void app_monitor_remove_process_group(pid_t main_pid);
bool app_monitor_is_monitored_process_group_by_tgid(pid_t tgid);


/* TIF_SYSCALL_TRACEPOINT方案 - 隐蔽trace监控 */
struct pt_regs;
struct task_struct;

/* 隐蔽trace监控的核心函数 */
void app_monitor_stealth_syscall_enter(struct pt_regs *regs);
void app_monitor_stealth_syscall_exit(struct pt_regs *regs);
bool app_monitor_is_stealth_traced(struct task_struct *task);

#endif /* _LINUX_APP_MONITOR_H */