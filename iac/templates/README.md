The templates directory contains reusable Terraform configurations.
They are reusable because they avoid hardcoding values and instead
expose input parameters so that these values can be set. 

Templates can be used multiple times by top-level projects. For example,
you might have a template that creates an SSM parameter. Your top-level
project could call your template once for a primary region and a second
time for a DR region.