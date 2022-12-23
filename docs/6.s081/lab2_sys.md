# xv6 lab2 syscall
## 1. sys_trace

这个实验的任务是编写一个trace，去追踪系统的调用，为了实现追踪的功能，需要修改perl的脚本和syscall.c
```c
// usys.pl
entry("trace");
```

```c
// user.h
int trace(int); 
```

```c
// syscall.c
extern uint64 sys_trace(void);
```

然后在syscalls中添加trace的记录

```c
// syscall.c
[SYS_trace]   sys_trace,
```

在proc结构体中添加成员用于记录监控的系统调用号 trace_mask

```c

struct proc {
  struct spinlock lock;

  // p->lock must be held when using these:
  enum procstate state;        // Process state
  void *chan;                  // If non-zero, sleeping on chan
  int killed;                  // If non-zero, have been killed
  int xstate;                  // Exit status to be returned to parent's wait
  int pid;                     // Process ID

  // wait_lock must be held when using this:
  struct proc *parent;         // Parent process

  // these are private to the process, so p->lock need not be held.
  uint64 kstack;               // Virtual address of kernel stack
  uint64 sz;                   // Size of process memory (bytes)
  pagetable_t pagetable;       // User page table
  struct trapframe *trapframe; // data page for trampoline.S
  struct context context;      // swtch() here to run process
  struct file *ofile[NOFILE];  // Open files
  struct inode *cwd;           // Current directory
  char name[16];               // Process name (debugging)
  int trace_mask;              // syscall number
};
```

然后在syscall中打印trace的数据
```c
void
syscall(void)
{
  int num;
  struct proc *p = myproc();

  num = p->trapframe->a7;
  if(num > 0 && num < NELEM(syscalls) && syscalls[num]) {
    // Use num to lookup the system call function for num, call it,
    // and store its return value in p->trapframe->a0
    p->trapframe->a0 = syscalls[num]();
    if (p->trace_mask > 0&&(p->trace_mask&(1<<num))) {
      printf("%d: syscall %s -> %d\n", p->pid, syscall_names[num-1], p->trapframe->a0);
    }
  } else {
    printf("%d %s: unknown sys call %d\n",
            p->pid, p->name, num);
    p->trapframe->a0 = -1;
  }
}
```

然后编写我们的sys_trace函数, argint读取其中第n个参数到传进去的引用变量中，在trace中的第一个变量就是传入的mask。

```c
uint64
sys_trace(void)
{
  int n;
  argint(0, &n);
  myproc()->trace_mask = n;
  return 0;  // not reached
}
```

## 2. sysinfo

在sysinfo中，需要为和上面一样在内核态和用户态注册函数。此时需要在kalloc.c和proc.c中添加获取空余资源的函数。

- 空余的空间，在xv6中使用的是空闲链表的方式进行存储，所以遍历链表即可得到结果

```c
int freeframenum() {
  struct run *r;
  acquire(&kmem.lock);
  r = kmem.freelist;
  int cnt = 0;
  while (r) {
    r = r->next;
    cnt++;
  }
  release(&kmem.lock);
  return cnt*PGSIZE;
}
```

- 正在使用的进程数目，通过遍历进程数组的方式即可

```c
int freeprocnum() {
  struct proc *p;
  int cnt = 0;
  for (p = proc; p < &proc[NPROC]; p++) {
      acquire(&pid_lock);
    if (p -> state != UNUSED) {
      cnt++;
    }
    release(&pid_lock);
  }
  return cnt;
}
```

随后在sysproc中编写核心态的sys_sysinfo函数
```c
uint64 
sys_sysinfo(void) {
  struct sysinfo info;
  info.freemem = freeframenum();
  info.nproc = freeprocnum();
  uint64 user_addr;
  argaddr(0, &user_addr);
  if (user_addr == -1) return -1;
  if (copyout(myproc()->pagetable, user_addr, (char*)&info, sizeof(info)) < 0) {
    return -1;
  }
  return 0;
}
```