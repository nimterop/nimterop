#ifdef __cplusplus
extern "C" {
#endif

#define A 1
#define B 1.0
#define C 0x10
#define D "hello"
#define E 'c'
#define F 01234

#define UEXPR (1234u << 1)
#define ULEXPR (1234ul << 2)
#define ULLEXPR (1234ull << 3)
#define LEXPR (1234l << 4)
#define LLEXPR (1234ll << 5)

#define SHL1 (1u << 1)
#define SHL2 (1u << 2)
#define SHL3 (1u << 3)
#define COERCE 645635634896ull + 35436
#define COERCE2 645635634896 + 35436ul
#define BINEXPR ~(-(1u << !-1)) ^ (10 >> 1)
#define POINTEREXPR (int*)0
#define POINTERPOINTERPOINTEREXPR (int***)0
#define BOOL true
#define MATHEXPR (1 + 2/3*20 - 100)
#define ANDEXPR (100 & 11000)
#define CASTEXPR (char) 34
#define AVAL 100
#define BVAL 200
#define EQ1 AVAL <= BVAL
#define EQ2 AVAL >= BVAL
#define EQ3 AVAL > BVAL
#define EQ4 AVAL < BVAL
#define EQ5 AVAL != BVAL
#define EQ6 AVAL == BVAL

// testing integer out of long int range
#define INT_FAST16_MIN (-9223372036854775807L-1)

#define SIZEOF sizeof(char)
#define REG_STR "regular string"
#define NOTSUPPORTEDSTR "not a " REG_STR

#define NULLCHAR '\0'
#define OCTCHAR '\012'
#define HEXCHAR '\xFE'
#define TRICKYSTR "\x4E\034\nfoo\0\'\"\r\v\a\b\e\f\t\\\?bar"

#define ALLSHL (SHL1 | SHL2 | SHL3)

#ifdef NIMTEROP
#define SOME_CONST 8
#endif

struct some_struct_s
{
  int x;
};

struct parent_struct_s
{
  struct some_struct_s s[SOME_CONST];
};

typedef struct some_struct_s SOME_ARRAY[SOME_CONST];

struct A0;
struct A1 {};
typedef struct A2;
typedef struct A3 {};
typedef struct A4 A4, *A4p;
typedef const int A5;
typedef int *A6;
typedef struct A0 **A7;
typedef void *A8;

// Forward declaration
struct A0 {
  int f1;
};

struct A4 {
  float f1;
};

typedef char *A9p[3], A9[4];
typedef char *A10[3][6];
typedef char *(*A11)[3];
typedef struct A0 *A111[12];

typedef int
  **(*A12)(int, int b, int *c, int *, int /*out*/ *count[4], int (*func)(int, int)),
  **(*A121)(float, float b, float *c, float *, float *count[4], float (*func)(float, float)),
  **(*A122)(char, char b, char *c, char *, char *count[4], char (*func)(char, char));
typedef int (*A13)(int, int, void (*func)(void));

struct A14 { volatile char a1; };
struct A15 { char *a1; const int *a2[1]; };

typedef struct A16 { char f1; };
typedef struct A17 { char *a1; int *a2[1]; } A18, *A18p;
typedef struct { char *a1; int *a2[1]; } A19, *A19p;

typedef struct A20 { char a1; } A20, A21, *A21p;

//Expression
typedef struct A22 { const int **f1; int *f2[123+132]; } A22;

//Unions
union U1 {int f1; float f2; };
typedef union U2 { const int **f1; int abc[123+132]; } U2;

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

// Proc vars
void
  *(*pcre_malloc)(size_t, ...),
  (*pcre_free)(void *),
  *(*pcre_stack_malloc)(size_t);

typedef int ImageView, MagickBooleanType;
typedef MagickBooleanType
  (*DuplexTransferImageViewMethod)(const ImageView *,const ImageView *,
    ImageView *,const size_t,const int,void *),
  (*GetImageViewMethod)(const ImageView *,const size_t,const int,void *),
  (*SetImageViewMethod)(ImageView *,const size_t,const int,void *),
  (*TransferImageViewMethod)(const ImageView *,ImageView *,const size_t,
    const int,void *),
(*UpdateImageViewMethod)(ImageView *,const size_t,const int,void *);

// Issue #156, math.h
void
  *absfunptr1 (int (*)(struct A0 *)),
  **absfunptr2 (int (**)(struct A1 *)),
  absfunptr3 (int *(*)(struct A2 *)),
  *absfunptr4 (int *(**)(struct A3 *)),
  absfunptr5 (int (*a)(A4 *));

int sqlite3_bind_blob(struct A1*, int, const void*, int n, void(*)(void*));

// Issue #174 - type name[] => UncheckedArray[type]
int ucArrFunc1(int text[]);
int ucArrFunc2(int text[][5], int (*func)(int text[]));

typedef int ucArrType1[][5];
struct ucArrType2 {
    float f1[5][5];
    int *f2[][5];
};

typedef struct fieldfuncfunc {
    int *(*func1)(int f1, int *(*sfunc1)(int f1, int *(*ssfunc1)(int f1, ...)));
};

int *func2(int f1, int *(*sfunc2)(int f1, int *(*ssfunc2)(int f1)));

typedef struct {
 const char *name; // description
 const char *driver; // driver
 int flags;
} BASS_DEVICEINFO;

// Issue #183
struct GPU_Target
{
    int w, *h;
    char *x, y, **z;
};

// Issue #185
struct SDL_AudioCVT;

typedef struct SDL_AudioCVT
{
    int needed;
}  SDL_AudioCVT;

// Issue #172
typedef struct {
  const char* const* x;
} SomeType;

// Nested #137
typedef struct {
    struct NT1 { int f1; } f1;
    struct { int f1; } f2;

    struct NT3 {
        struct {
            int f1;
            union NU1 {
                float f1;
            } f2;
            enum { NEV1, NEV2, NEV3 } f3;
        } f1;
     } f3;

    struct { int f1; } f4;

    union NU2 { int f1; } f5;
    union { int f1; } f6;
    enum NE1 { NEV4 = 8, NEV5 } f7;
    enum { NEV6 = 8 * 8, NEV7 } f8;
} nested;

static inline int sitest1(int f1) {
  return f1 * 2;
}

// Issue #196
typedef int MyInt;
struct TestMyInt {
  MyInt f1;
};



// DUPLICATES

#ifdef NOHEADER

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
typedef struct A0 **A7;
typedef void *A8;

// Forward declaration
struct A0 {
  int f1;
};

struct A4 {
  float f1;
};

typedef char *A9p[3], A9[4];
typedef char *A10[3][6];
typedef char *(*A11)[3];
typedef struct A0 *A111[12];

typedef int
  **(*A12)(int, int b, int *c, int *, int *count[4], int (*func)(int, int)),
  **(*A121)(float, float b, float *c, float *, float *count[4], float (*func)(float, float)),
  **(*A122)(char, char b, char *c, char *, char *count[4], char (*func)(char, char));
typedef int A13(int, int, void (*func)(void));

struct A14 { volatile char a1; };
struct A15 { char *a1; const int *a2[1]; };

typedef struct A16 { char f1; };
typedef struct A17 { char *a1; int *a2[1]; } A18, *A18p;
typedef struct { char *a1; int *a2[1]; } A19, *A19p;

typedef struct A20 { char a1; } A20, A21, *A21p;

//Expression
typedef struct A22 { const int **f1; int *f2[123+132]; } A22;

//Unions
union U1 {int f1; float f2; };
typedef union U2 { const int **f1; int abc[123+132]; } U2;

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

// Proc vars
void
  *(*pcre_malloc)(size_t, ...),
  (*pcre_free)(void *),
  *(*pcre_stack_malloc)(size_t);

typedef int ImageView, MagickBooleanType;
typedef MagickBooleanType
  (*DuplexTransferImageViewMethod)(const ImageView *,const ImageView *,
    ImageView *,const size_t,const int,void *),
  (*GetImageViewMethod)(const ImageView *,const size_t,const int,void *),
  (*SetImageViewMethod)(ImageView *,const size_t,const int,void *),
  (*TransferImageViewMethod)(const ImageView *,ImageView *,const size_t,
    const int,void *),
(*UpdateImageViewMethod)(ImageView *,const size_t,const int,void *);

// Issue #156, math.h
void
  *absfunptr1 (int (*)(struct A0 *)),
  **absfunptr2 (int (**)(struct A1 *)),
  absfunptr3 (int *(*)(struct A2 *)),
  *absfunptr4 (int *(**)(struct A3 *)),
  absfunptr5 (int (*a)(A4 *));

int sqlite3_bind_blob(struct A1*, int, const void*, int n, void(*)(void*));

typedef struct fieldfuncfunc {
    int *(*func1)(int f1, int *(*sfunc1)(int f1, int *(*ssfunc1)(int f1, ...)));
};

int *func2(int f1, int *(*sfunc2)(int f1, int *(*ssfunc2)(int f1)));

typedef struct {
 const char *name; // description
 const char *driver; // driver
 int flags;
} BASS_DEVICEINFO;

// Issue #183
struct GPU_Target
{
    int w, *h;
    char *x, y, **z;
};

// Issue #185
struct SDL_AudioCVT;

typedef struct SDL_AudioCVT
{
    int needed;
}  SDL_AudioCVT;

// Issue #172
typedef struct {
  const char* const* x;
} SomeType;

// Nested #137
typedef struct {
    struct NT1 { int f1; } f1;
    struct { int f1; } f2;

    struct NT3 {
        struct {
            int f1;
            union NU1 {
                float f1;
            } f2;
            enum { NEV1, NEV2, NEV3 } f3;
        } f1;
     } f3;

    struct { int f1; } f4;

    union NU2 { int f1; } f5;
    union { int f1; } f6;
    enum NE1 { NEV4 = 8, NEV5 } f7;
    enum { NEV6 = 8 * 8, NEV7 } f8;
} nested;

static inline int sitest1(int f1) {
  return f1 * 2;
}

// Issue #196
typedef int MyInt;
struct TestMyInt {
  MyInt f1;
};



#endif

#ifdef __cplusplus
}
#endif
