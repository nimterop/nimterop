#define TEST_INT 512

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


