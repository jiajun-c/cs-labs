
# xv6 lab4 traps

## 1. Backtrace

通过fp寄存器进行函数的递归，得到函数的调用栈。fp寄存器指向的位置是当前栈的栈底部，所以其向下8个字节位置的数据为ra，向下16个字节位置的数据为fp寄存器

核心代码如下所示

```c
void backtrace() {
  printf("in bt\n");
  // 帧指针下面的是返回地址
  // 再下面一个是上一个栈帧的帧指针
  uint64 cur_frame = r_fp();
  uint64 top = PGROUNDUP((uint64)cur_frame);
  uint64 bot = PGROUNDDOWN((uint64)cur_frame);
  while(cur_frame < top && cur_frame > bot){
    printf("%p\n", *(uint64*)(cur_frame-8)); // 先打印当前的返回地址
    cur_frame =  *(uint64*)(cur_frame-16); // 然后把当前栈帧变成上一个栈帧
  }
}
```

## 2. Alarm

首先在proc结构体中添加alarm相关的成员，记录过去的时间和alarm处理函数

```c
  int alarm_interval;
  int alarm_passed;
  uint64 alarm_handler;
```

为了完善系统调用，添加系统调用号
```c
[SYS_sigalarm] sys_sigalarm,
```

添加函数获取参数
```c
uint64
sys_sigalarm(void)
{
  int interval;
  argint(0, &interval);

  uint64 handler;
  argaddr(1, &handler);
  printf("%d %d\n",interval, handler);
  myproc()->alarm_handler = handler;
  myproc()->alarm_interval = interval;
  return 0;
}
```

在usertrap中判断是否是一个时钟中断，如果是一个时钟中断，判断此时是否进行时钟中断函数，当到达限定的时间后触发函数

```c
  if(which_dev == 2) {
    if (p->alarm_interval) {
      if (++p->alarm_passed == p->alarm_interval) {
        memmove(&(p->eptfm), p->trapframe, sizeof(p->eptfm));
        p->trapframe->epc = p->alarm_handler;
      }
    }
    yield();
  }
```

在结束后，清除计数器


