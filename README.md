## How to deploy Warp app
1. Configure local AWS CLI profile and login to registry you want to use (e.g. Docker Hub).
2. Move to the root folder of project.
3. Set up your variables in 'Makefile' file.
4. To build & push image and deploy ECS cluster (with all dependencies) run:
```
$ make all
```
5. If you want to spin up environment with existing images run:
```
$ make deploy
```
6. To use application paste DNS name of ALB into browser's search bar. You can find it in Terraform output variable "alb-dns-name".
7. Use the following credentials to login.
```
username: admin
password: noneshallpass
```
8. To clean up resources run "terraform destroy" in terraform/ folder.

## What was done
1. Created terrafom/ folder with all needed files to spin up infrastructure.
2. Created separate nginx config file for ECS environment. 
3. Created separate nginx docker image.
4. Created Makefile.
5. Changed gitignore to be appropriate to terraform code.
