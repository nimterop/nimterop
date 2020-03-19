
#define A 1
#define B 1.0
#define C 0x10
#define D "hello"
#define E 'c'

struct A0;
struct A1 {};
typedef struct A2;
typedef struct A3 {};
typedef struct A4 A4, *A4p;
typedef const int A5;
typedef int *A6;
typedef A0 **A7;
typedef void *A8;

typedef char *A9p[3]; //, A9[4];
typedef char *A10[3][6];
typedef char *(*A11)[3];

typedef int **(*A12)(int, int b, int *c, int *, int *count[4], int (*func)(int, int));
typedef int A13(int, int);

struct A14 { volatile char a1; };
struct A15 { char *a1; const int *a2[1]; };

typedef struct A16 { char f1; };
typedef struct A17 { char *a1; int *a2[1]; } A18, *A18p;
typedef struct { char *a1; int *a2[1]; } A19, *A19p;

typedef struct A20 { char a1; } A20, A21, *A21p;

//Expression
typedef struct A22 { int **f1; int *f2[123+132]; } A22;

//Unions
union U1 {int f1; float f2; };
typedef union U2 { int **f1; int abc[123+132]; } U2;

// Anonymous
//typedef struct { char a1; };

//struct A2 test_proc1(struct A0 a);