#include "test.h"

int test_call_int() {
	return 5;	
}

struct STRUCT1 test_call_int_param(int param1) {
	struct STRUCT1 s;
	
	s.field1 = param1;
	
	return s;
}

STRUCT2 test_call_int_param2(int param1, STRUCT2 param2) {
	STRUCT2 s;
	
	s.field1 = param1 + param2.field1;
	
	return s;
}

STRUCT2 test_call_int_param3(int param1, struct STRUCT1 param2) {
	STRUCT2 s;
	
	s.field1 = param1 + param2.field1;
	
	return s;
}

ENUM2 test_call_int_param4(enum ENUM param1) {
	return enum4;
}