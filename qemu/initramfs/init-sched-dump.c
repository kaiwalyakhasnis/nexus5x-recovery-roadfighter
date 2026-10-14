/* Minimal freestanding init: dumps scheduler/governor info, then idles. */
typedef unsigned long u64;
static long sc(long n,long a,long b,long c,long d,long e){
  register long x8 asm("x8")=n,x0 asm("x0")=a,x1 asm("x1")=b,x2 asm("x2")=c,x3 asm("x3")=d,x4 asm("x4")=e;
  asm volatile("svc 0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3),"r"(x4):"memory"); return x0;}
#define AT_FDCWD -100
static int sl(const char*s){int n=0;while(s[n])n++;return n;}
static long ofd=1;
static void wr(const char*s,long n){sc(64,ofd,(long)s,n,0,0);}
static void out(const char*s){wr(s,sl(s));}
static void cat(const char*p){char b[4096];long fd=sc(56,AT_FDCWD,(long)p,0,0,0);
  out("== ");out(p);out("\n");if(fd<0){out("  (missing)\n");return;}
  long n;while((n=sc(63,fd,(long)b,sizeof b,0,0))>0){long i,j=0;for(i=0;i<n;i++)if(b[i]==10){wr(b+j,i-j+1);j=i+1;}if(j<n)wr(b+j,n-j);};sc(57,fd,0,0,0,0);}
void _start(void){
  sc(40,0,(long)"/proc",(long)"proc",0,0); sc(40,0,(long)"/sys",(long)"sysfs",0,0);
  long k=sc(56,AT_FDCWD,(long)"/dev/kmsg",1,0,0); if(k>=0)ofd=k;
  out("\n*** bullhead kernel userspace init running ***\n");
  const char*f[]={"/proc/version","/proc/cpuinfo","/proc/sys/kernel/sched_upmigrate","/proc/sys/kernel/sched_downmigrate",
   "/proc/sys/kernel/sched_boost","/proc/sys/kernel/sched_window_stats_policy","/proc/sys/kernel/sched_ravg_window",
   "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor","/proc/self/sched","/proc/schedstat",0};
  for(int i=0;f[i];i++)cat(f[i]);
  out("*** done; idling ***\n"); for(;;){struct{long s,n;}t={60,0};sc(101,(long)&t,0,0,0,0);}
}
