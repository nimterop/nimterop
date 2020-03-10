
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

typedef char *A9[3];
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
//typedef struct A21 { int **f1; int abc[123+132]; } A21;

//Unions
//union UNION1 {int f1; };
//typedef union UNION2 { int **f1; int abc[123+132]; } UNION2;

// Anonymous
//typedef struct { char a1; };
