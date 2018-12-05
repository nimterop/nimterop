#include "test.h"

int test_call_int() {
	return 5;
}

#ifdef FORCE
struct STRUCT1 _test_call_param_(int param1) {
	struct STRUCT1 s;

	s.field1 = param1;

	return s;
}
#endif

STRUCT2 test_call_param2(int param1, STRUCT2 param2) {
	STRUCT2 s;

	s.field1 = param1 + param2.field1;

	return s;
}

STRUCT2 test_call_param3(int param1, struct STRUCT1 param2) {
	STRUCT2 s;

	s.field1 = param1 + param2.field1;

	return s;
}

ENUM2 test_call_param4(enum ENUM param1) {
	return enum4;
}

union UNION1 test_call_param5(float param1) {
	union UNION1 u;

	u.field2 = param1;

	return u;
}

unsigned char test_call_param6(UNION2 param1) {
	return param1.field2;
}

int test_call_param7(union UNION1 param1) {
	return param1.field1;
}