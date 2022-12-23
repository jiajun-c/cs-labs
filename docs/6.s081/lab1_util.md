# xv6 lab1 utils
## 0. 前置知识

## xv6的系统调用
提供了如下的接口
![image.png](https://s2.loli.net/2022/12/21/bWVjC1DXKmcEF3w.png)

## 文件描述符和IO

文件描述符表示的是由内核管理的一个进程读或者写的目的地，进程通过打开文件，设备，文件夹，pipe获取到文件描述符。

## pipe的使用

pipe是一个小型的buf，使用pipe的时候需要int p[2] 类型的参数，将一个作为读的文件描述符，一个作为写的文件描述符，在本例中p[1]是写入的文件描述符，p[0]是输出读的文件描述符

如果需要在两个进程之间传递参数，那么此时可能需要两个pipe

## 1. sleep

在这里的sleep实现是在user中编写sleep函数，然后在UPROGS中加入sleep使得其可以被编译得到可执行的文件

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int
main(int argc, char const *argv[])
{
    if (argc < 2) {
        fprintf(2, "too few arguments");
        exit(0);
    }
    int n = atoi(argv[1]);
    sleep(n);
    exit(0);
}
```

修改Makefile

```shell
UPROGS=\
	$U/_cat\
	$U/_echo\
	$U/_forktest\
	$U/_grep\
	$U/_init\
	$U/_kill\
	$U/_ln\
	$U/_ls\
	$U/_mkdir\
	$U/_rm\
	$U/_sleep\
	$U/_sh\
	$U/_stressfs\
	$U/_usertests\
	$U/_grind\
	$U/_wc\
	$U/_zombie\

```

## 2. pingpong

pingpong中使用两个pipe对发送方和接收方进行分别的缓存，然后两边对数据进行读写的操作。当对一个管道进行读的时候，需要先关闭写通道，在读完成后，需要关闭读的通道

如下所示
```cpp
        close(ping[READ]);
        write(ping[WRITE], "ping\n", 5);
        close(ping[WRITE]);
```

最终实现的如下所示

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#define READ 0
#define WRITE 1
int main(int argc, char const *argv[])
{
    int ping[2], pong[2];
    pipe(ping);
    pipe(pong);
    if (fork() == 0) {
        char buf[8];
        close(ping[1]);
        read(ping[0], buf, sizeof buf);
        close(ping[0]);
        close(pong[0]);
        write(pong[WRITE], "pong\n", 5);
        close(pong[WRITE]);
        printf("%d: received %s", getpid(), buf);
        exit(0);
    } else {
        char buf[8];
        close(ping[READ]);
        write(ping[WRITE], "ping\n", 5);
        close(ping[WRITE]);

        close(pong[WRITE]);
        read(pong[READ], buf, sizeof buf);
        close(pong[READ]);
        
        wait(0);
        printf("%d: received %s", getpid(), buf);
        exit(0);
    }
}
```

## 3. primes

primes中需要实现的是一个并发的筛法，其原理类似我们的线性筛法，在一个阶段取出其中最小的那个数，然后将数据中可以被该数整除的数不传递到下一个子进程中。

![image.png](https://s2.loli.net/2022/12/22/LZkrqUJNR2tAsHQ.png)

```C
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#define READ 0
#define WRITE 1
int main(int argc, char const *argv[])
{
    int pipe_parent[2];
    pipe(pipe_parent);
    if (fork() > 0) {
        close(pipe_parent[READ]);
        for (int i = 2; i <= 35; i++) {
            write(pipe_parent[WRITE], &i, sizeof i);
        }
        close(pipe_parent[WRITE]);
        wait((int *)0);
        exit(0);
    } else {
        int now;
        close(pipe_parent[WRITE]);
        while (read(pipe_parent[READ], &now, sizeof now)) {
            printf("prime %d\n", now);
            int pipe_child[2];
            pipe(pipe_child);
            int i;
            while (read(pipe_parent[READ], &i, sizeof i)) {
                if (i%now)
                    write(pipe_child[WRITE], &i, sizeof i);
            }
            close(pipe_child[WRITE]);
            // if (fork() == 0) {
            pipe_parent[READ] = dup(pipe_child[READ]);
            close(pipe_child[READ]);
            // } else {
                // close(pipe_child[READ]);
                // wait((int *)0);
                // exit(0);
            // }
        }
        exit(0);
    }
    return 0;
}

```


## 4. find

find的实现和ls是相似，但是需要改动一下后面的类型处理，如果当前的路径不是一个文件夹那么此时可以直接进行返回，如果是一个文件夹，那么此时遍历下面的数据，如果是文件夹那么进行递归的访问，如果不是那么直接比较名字即可。

```c
void find(const char* path,const char * filename) {
    char buf[512], *p;
    int fd;
    strcpy(buf, path);
    p = buf + strlen(path);
    *p++ = '/';
    struct dirent de;
    struct stat st;
    if ((fd = open(path, 0)) < 0) {
        fprintf(2, "find: can not open the %s\n", path);
        close(fd);
    }
    if(fstat(fd, &st) < 0){
        fprintf(2, "ls: cannot stat %s\n", path);
        close(fd);  
        return; 
    }
    if (st.type != T_DIR) {
        fprintf(2, "find: %s is not a dir");
        close(fd);
        return;
    }
    while(read(fd, &de, sizeof(de)) == sizeof(de)){
        if (de.inum == 0) continue;
        char *name = de.name;
        if (strcmp(name, ".")==0 || strcmp(name, "..")==0) continue;
        memmove(p, de.name, DIRSIZ);
        p[DIRSIZ] = 0;
        if(stat(buf, &st) < 0){
            printf("find: cannot stat %s\n", buf);
            continue;
        }
        if (st.type == T_DIR) {
            find(buf, filename);
        } else if (!strcmp(filename, name)) {
            printf("%s\n",buf);
        }
    }
    close(fd);
}
```

## 5 xargs

xargs的功能在于将管道符前面的输入作为后面的参数进行使用，这个时候我们需要对标准输入进行处理。

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fs.h"

void xargs(int argc, char* argv[]) {
    int count = 0;
    char* argvs[32];
    for (int i = 1; i < argc; i++) {
        argvs[count++] = argv[i];
    }
    char buf[512];
    char*p = buf, *pre = buf;
    while (read(0, p, 1) == 1)
    {
        if (*p == '\n') {
            *p = 0;
            argvs[count++] = pre;
            argvs[count] = 0;
            pre = p + 1;
        } else if (*p ==' '){
            *p =0;
            argvs[count++] = pre;
            pre = p+1;
        }
        p++;
    }
    fprintf(0, "%s\n", argvs[0]);
    exec(argvs[0], argvs);
    exit(0);
}
int main(int argc, char *argv[])
{
    /* code */
    if (argc < 2) {
        fprintf(2, "Too few argument");
        exit(1);
    }
    xargs(argc, argv);
    return 0;
}
 
```

测试结果
```shell
== Test find, recursive == 
$ make qemu-gdb
find, recursive: OK (1.1s) 
== Test xargs == 
$ make qemu-gdb
xargs: OK (1.1s) 
== Test time == 
time: OK 
Score: 100/100
```