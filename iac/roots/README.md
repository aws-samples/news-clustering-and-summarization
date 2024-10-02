The roots directory should include all top-level Terraform projects.

A top-level project is defined as a directory containing a main.tf file
that you would want to run "terraform apply" on. Each top-level project
has its own separate Terraform state file.

Top-level projects should make use of reusable components and modules,
which are located under the "templates" directory. Essentially, your
top-level projects should not define any behavior on their own. They simply 
define input variables and make calls to reusable templates.