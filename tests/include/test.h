#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

#define TEST_INT 512
#define TEST_FLOAT 5.12
#define TEST_HEX 0x512

#ifdef __APPLE__
#define OSDEF 10
#endif

#ifdef _WIN32
#define OSDEF 20
#endif

#ifdef __linux__
#define OSDEF 30
#endif

#define foobar1(x) OSDEF * x
#define foobar2(x) x + 1

typedef uint8_t PRIMTYPE;
typedef PRIMTYPE CUSTTYPE;

struct STRUCT0;

struct STRUCT1 {
	int field1;
};

typedef struct STRUCT1 STRUCT2;

typedef struct {
	int field1;
} STRUCT3;

enum ENUM {
	enum1,
	enum2,
	enum3
};

typedef enum {
	enum4 = 3,
	enum5,
	enum6
} ENUM2;

enum {
	enum7,
	enum8,
	enum9
};

typedef enum ENUM4 {
	enum10,
	enum11,
	enum12
} ENUM4;

enum ENUM5 {
	enum13 = (1 << 2),
	enum14 = ((1 << 3) | 1),
	enum15 = (1 << (1 & 1))
};

typedef void * VOIDPTR;
typedef int * INTPTR;

typedef struct {
	int *field;
	int field2[TEST_INT];
	enum ENUM field3[TEST_INT];
	int *field4[TEST_INT];
	ENUM4 *field5[TEST_INT+TEST_INT];
} STRUCT4;

typedef struct struct5 {
	int (*tci)();
	struct STRUCT1 (*tcp)(int);
	float (*tcp8)(int *i);
	void *(*tcv)();
} STRUCT5;

union UNION1 {
	int field1;
	float field2;
};

typedef union UNION2 {
	double field1;
	unsigned char field2;
} UNION2;

int test_call_int();
struct STRUCT1 _test_call_param_(int param1);
STRUCT2 test_call_param2(int param1, STRUCT2 param2);
STRUCT2 test_call_param3(int param1, struct STRUCT1 param2);
ENUM2 test_call_param4(enum ENUM param1);
union UNION1 test_call_param5(float param1);
unsigned char test_call_param6(UNION2 param1);
int test_call_param7(union UNION1 param1);
float test_call_param8(int *param1);
void *test_call9();
void **test_call10(int **param1);

// Issue #58
void
  multiline1(void),
  *multiline2(void),
  multiline3(void);

// Issue #52
typedef struct struct6 { char name; } *STRUCT6;
typedef enum enum6t { enum16 } *ENUM6;
typedef union union3 { char name; } *UNION3;

struct struct6 test_call_stype6();
STRUCT6 test_call_stype_ptr6();

enum enum6t test_call_etype6();
ENUM6 test_call_etype_ptr6();

union union3 test_call_utype3();
UNION3 test_call_etype_ptr3();

typedef struct _Kernel { char name; } *Kernel;

// Double pointers
typedef void **DVOIDPTR;
typedef int **DINTPTR;

struct dstruct {
  int **field1;
};

typedef struct dstruct2 {
  char **field1;
  float **field2;
	void **(*tcv)(int **param1);
} DSTRUCT2;

#ifdef __cplusplus
}
#endif