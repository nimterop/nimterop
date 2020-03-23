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

// Forward declaration
struct A0 {
  int f1;
};

typedef char *A9p[3]; //, A9[4];
typedef char *A10[3][6];
typedef char *(*A11)[3];
typedef struct A1 *A111[12];

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

// Enums

// Issue #159
#define NK_FLAG(x) (1 << (x))
enum nk_panel_type {
    NK_PANEL_NONE       = 0,
    NK_PANEL_WINDOW     = NK_FLAG(0),
    NK_PANEL_GROUP      = NK_FLAG(1),
    NK_PANEL_POPUP      = NK_FLAG(2),
    NK_PANEL_CONTEXTUAL = NK_FLAG(4),
    NK_PANEL_COMBO      = NK_FLAG(5),
    NK_PANEL_MENU       = NK_FLAG(6),
    NK_PANEL_TOOLTIP    = NK_FLAG(7)
};
enum nk_panel_set {
    NK_PANEL_SET_NONBLOCK = NK_PANEL_CONTEXTUAL|NK_PANEL_COMBO|NK_PANEL_MENU|NK_PANEL_TOOLTIP,
    NK_PANEL_SET_POPUP = NK_PANEL_SET_NONBLOCK|NK_PANEL_POPUP,
    NK_PANEL_SET_SUB = NK_PANEL_SET_POPUP|NK_PANEL_GROUP
};

// Issue #171
typedef enum VSColorFamily {
    /* all planar formats */
    cmGray   = 1000000,
    cmRGB    = 2000000,
    cmYUV    = 3000000,
    cmYCoCg  = 4000000,
    /* special for compatibility */
    cmCompat = 9000000
} VSColorFamily;

typedef enum VSPresetFormat {
    pfNone = 0,

    pfGray8 = cmGray + 10,
    pfGray16,

    pfYUV420P8 = cmYUV + 10,
    pfYUV422P8,

    pfRGB24 = cmRGB + 10,
    pfRGB27,
    /* test */

    pfCompatBGR32 = cmCompat + 10,
    pfCompatYUY2
} VSPresetFormat;

// Anonymous
//typedef struct { char a1; };

//struct A2 test_proc1(struct A0 a);







// DUPLICATES

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

// Forward declaration
struct A0 {
  int f1;
};

typedef char *A9p[3]; //, A9[4];
typedef char *A10[3][6];
typedef char *(*A11)[3];
typedef struct A1 *A111[12];

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

// Enums

// Issue #159
#define NK_FLAG(x) (1 << (x))
enum nk_panel_type {
    NK_PANEL_NONE       = 0,
    NK_PANEL_WINDOW     = NK_FLAG(0),
    NK_PANEL_GROUP      = NK_FLAG(1),
    NK_PANEL_POPUP      = NK_FLAG(2),
    NK_PANEL_CONTEXTUAL = NK_FLAG(4),
    NK_PANEL_COMBO      = NK_FLAG(5),
    NK_PANEL_MENU       = NK_FLAG(6),
    NK_PANEL_TOOLTIP    = NK_FLAG(7)
};
enum nk_panel_set {
    NK_PANEL_SET_NONBLOCK = NK_PANEL_CONTEXTUAL|NK_PANEL_COMBO|NK_PANEL_MENU|NK_PANEL_TOOLTIP,
    NK_PANEL_SET_POPUP = NK_PANEL_SET_NONBLOCK|NK_PANEL_POPUP,
    NK_PANEL_SET_SUB = NK_PANEL_SET_POPUP|NK_PANEL_GROUP
};

// Issue #171
typedef enum VSColorFamily {
    /* all planar formats */
    cmGray   = 1000000,
    cmRGB    = 2000000,
    cmYUV    = 3000000,
    cmYCoCg  = 4000000,
    /* special for compatibility */
    cmCompat = 9000000
} VSColorFamily;

typedef enum VSPresetFormat {
    pfNone = 0,

    pfGray8 = cmGray + 10,
    pfGray16,

    pfYUV420P8 = cmYUV + 10,
    pfYUV422P8,

    pfRGB24 = cmRGB + 10,
    pfRGB27,
    /* test */

    pfCompatBGR32 = cmCompat + 10,
    pfCompatYUY2
} VSPresetFormat;

// Anonymous
//typedef struct { char a1; };

//struct A2 test_proc1(struct A0 a);