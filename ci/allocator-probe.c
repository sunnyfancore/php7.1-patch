/* Test-only extension: exercise an allocation size not expressible by a PHP int. */
#include "php.h"

PHP_FUNCTION(audit_huge_allocation)
{
	_emalloc_huge((size_t)-1);
	RETURN_NULL();
}

static const zend_function_entry audit_functions[] = {
	PHP_FE(audit_huge_allocation, NULL)
	PHP_FE_END
};

zend_module_entry allocator_probe_module_entry = {
	STANDARD_MODULE_HEADER,
	"allocator_probe", audit_functions,
	NULL, NULL, NULL, NULL, NULL,
	"1", STANDARD_MODULE_PROPERTIES
};

ZEND_GET_MODULE(allocator_probe)
