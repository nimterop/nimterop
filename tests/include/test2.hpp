#include <stdint.h>

#define TEST_INT 512
#define TEST_FLOAT 5.12
#define TEST_HEX 0x512

int test_call_int();

struct Foo{
  int bar;
};

class Foo1{
  int bar1;
};

template<typename T>
struct Foo2{
  int bar2;
};

typedef Foo2<int> Foo2_int;


