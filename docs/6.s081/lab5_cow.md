# xv6 lab5 cow
Cow，这个实验大致的意思就是对一个fork而言，不会创建新的页面，而是将该页面变为只读的页面，供两个进程共享，如果当一个进程尝试去写页面，那么次数将导致一个fault，此时再为其分配一个新的页面

为了标记我们的页表，在 8到10位的数据为空闲，供操作系统使用，此时我们将第8位的数据用于标志该页面为cow页面。

```c
#define PTE_V (1L << 0) // valid
#define PTE_R (1L << 1)
#define PTE_W (1L << 2)
#define PTE_X (1L << 3)
#define PTE_U (1L << 4) // user can access
#define PTE_C (1L << 8)
```

为了标记页面使用的情况，我们使用一个数据结构存储页面相关信息

```c
struct
{
  struct spinlock lock;
  uint counter[(PHYSTOP - KERNBASE)/PGSIZE];
}refcnt;
```

此时对于页面的分配回收机制将发生改变，在进行分配时，需要将引用计数器设置为1

```c
void *
kalloc(void)
{
  struct run *r;

  acquire(&kmem.lock);
  r = kmem.freelist;
  if (r)
    set_refcnt((uint64)r, 1);
  if(r)
    kmem.freelist = r->next;
  release(&kmem.lock);
  if(r)
    memset((char*)r, 5, PGSIZE); // fill with junk
  return (void*)r;
}
```

在页面的回收时，如果其页面引用计数器没有被清零，那么无法真正清空页面

```c
void
kfree(void *pa)
{
  struct run *r;

  if(((uint64)pa % PGSIZE) != 0 || (char*)pa < end || (uint64)pa >= PHYSTOP)
    panic("kfree");
  acquire_refcnt();
  if (refcnt.counter[pgindex((uint64)pa)] > 1) {
    refcnt.counter[pgindex((uint64)pa)]--;
    release_refcnt();
    return;
  }
  // Fill with junk to catch dangling refs.
  memset(pa, 1, PGSIZE);
  set_refcnt((uint64)pa, 0);
  release_refcnt();
  
  r = (struct run*)pa;
  
  acquire(&kmem.lock);
  r->next = kmem.freelist;
  kmem.freelist = r;
  release(&kmem.lock);
}
```

通过cow-copy函数，当其遇到对页面写的情况，创建新的物理页

```c
int 
cowcopy(uint64 va) {
  va = PGROUNDDOWN(va);
  pagetable_t p = myproc()->pagetable;
  pte_t* pte = walk(p, va, 0);
  uint64 pa = PTE2PA(*pte);
  uint flags = PTE_FLAGS(*pte);
  if (!(flags&PTE_C)) {
    printf("no cow\n");
    return -2;
  }
  acquire_refcnt();
  uint cnt = get_refcnt(pa);
  if (cnt > 1) {
    char* mem = kalloc_nolock();
    if (!mem) goto bad;
    memmove(mem, (char*)pa, PGSIZE);
    if (mappages(p, va, PGSIZE, (uint64)mem, (flags&(~PTE_C))|PTE_W) !=0) {
      kfree(mem);
      goto bad;
    }
    set_refcnt(pa, cnt - 1);
  } else {
    *pte = ((*pte)&(~PTE_C))|PTE_W;
  }
  release_refcnt();
  return 0;
  bad:
  release_refcnt();
  return -1;
}
```

![image.png](https://s2.loli.net/2023/01/09/nsdKSOfeX4rayCc.png)

此时除法的page fault为15，需要在usertrap中对其进行处理。

```c
  } else if (r_scause() == 15) {
    uint64 va = r_stval();
    if (cowcopy(va) == -1) {
      p->killed = 1;
    }
```

为了获取此时的异常地址，使用stval

> 如果stval的值不为0，如果是 misaligned load、store causes an access-fault 或page-fault exception造成的，然后 stval 将包含导致故障的访问部分的虚拟地址。


