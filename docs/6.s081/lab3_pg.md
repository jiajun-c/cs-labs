# xv6 lab3 pgtbl

# 1. 加速系统调用

为了加速系统调用，需要添加共享页面，由内核态和用户态共享，共享的页面为 `USYSCALL`

首先需要在进程结构体中添加该成员，方便进行使用

```c
struct usyscall *usyscall; //
```

然后在初始化中对该成员进行初始化，为其分配空间，设置pid

```c
  if((p->usyscall = (struct usyscall *)kalloc()) == 0){
    freeproc(p);
    release(&p->lock);
    return 0;
  }
  p->usyscall->pid = p->pid;
```

然后我们需要对这个页进行映射，将物理地址和虚拟地址进行映射，这个页面需要被用户态所访问，所以U和R标志位需要为1，即PTE_U | PTE_R 

![image.png](https://s2.loli.net/2023/01/01/UpnP3WyaFJmdjZG.png)

```c
if(mappages(pagetable, USYSCALL, PGSIZE, (uint64)(p->usyscall), 
    PTE_R | PTE_U) < 0){
    // 映射完成后，我们访问 USYSCALL 开始的页，就会访问到 p->usyscall
    uvmunmap(pagetable, TRAMPOLINE, 1, 0);
    uvmunmap(pagetable, TRAPFRAME, 1, 0);
    uvmfree(pagetable, 0);
    return 0;
  }
  return pagetable;
}
```
在完成映射后还需要完成内存的回收, 以及接触映射

```c
uvmunmap(pagetable, USYSCALL, 1, 0);
```

使用kfree进行释放
```c
  if(p->usyscall)
    kfree((void*)p->usyscall);
  p->usyscall = 0;
```

# 2. Print a page table

这一关让我那么实现的是对页表的遍历，在xv6中使用的二级页表的方式。所以需要使用dfs的方式进行搜索，如果这个节点为指向下一层的指针，如下所示，即X W R三个位置都为0时。通知V位置需要为1，用于表示合法
![image.png](https://s2.loli.net/2023/01/01/hzt148lGAZeCvXD.png)
```c
void
freewalk(pagetable_t pagetable)
{
  // there are 2^9 = 512 PTEs in a page table.
  for(int i = 0; i < 512; i++){
    pte_t pte = pagetable[i];
    if((pte & PTE_V) && (pte & (PTE_R|PTE_W|PTE_X)) == 0){
      // this PTE points to a lower-level page table.
      uint64 child = PTE2PA(pte);
      freewalk((pagetable_t)child);
      pagetable[i] = 0;
    } else if(pte & PTE_V){
      panic("freewalk: leaf");
    }
  }
  kfree((void*)pagetable);
}
```

参考上面我们可以写出
```c
void vmprint(pagetable_t pagetable, uint dep) {
  if (dep == 0) printf("page table %p\n", pagetable);
  if (dep > 2) return;
  for (int i = 0; i < 512; i++) {
        pte_t pte = pagetable[i];
        if (pte&PTE_V) {
          for (int j = 0; j < dep; j++) {
            printf(".. ");
          }
          uint64 child = PTE2PA(pte);
          printf("..%d: pte %p pa %p\n", i, pte, child);
          vmprint((pagetable_t)child, dep+1);
        }
  }
}
```

# 3. Detect which pages have been accessed

使用bitmap的形式存储每个位的使用情况，传递给sys_pgacess中的有三个参数
- 起始的虚拟地址
- 需要检查的页面的数目
- 结果存储到用户态空间地址
使用walk获取页表列表， 在检查该页后清空PTE_A，`fir_pte[i] ^= PTE_A;`
```c
int
sys_pgaccess(void)
{
  // lab pgtbl: your code here.
  pagetable_t pt = myproc()->pagetable;
  uint64 va, user_addr;
  int page_num;
  argaddr(0, &va);
  argint(1, &page_num);
  argaddr(2, &user_addr);
  uint mask = 0;
  if (page_num > 32) return -1;
  pte_t* fir_pte = walk(pt, va, 0);
  for (int i = 0; i < page_num; i++) {
    if ((fir_pte[i]&PTE_A)&&(fir_pte[i]&PTE_V)) {
      // printf("%d \n",i);
      mask |= (1<<i);
      fir_pte[i] ^= PTE_A;
    }
  }
  // printf("%x\n", mask);
  copyout(pt, user_addr, (char*)&mask, sizeof(mask));
  return 0;
}
```


