NGINX_IMAGE_NAME=alexolink/warp-app-nginx
NGINX_IMAGE_TAG=v0.1
APP_IMAGE_NAME=alexolink/warp-app
APP_IMAGE_TAG=v0.1

all: build push deploy

build:
	docker build --platform=linux/amd64 -t $(NGINX_IMAGE_NAME):$(NGINX_IMAGE_TAG) -f Dockerfile.nginx .
	docker build --platform=linux/amd64 -t $(APP_IMAGE_NAME):$(APP_IMAGE_TAG) .

push:
	docker push $(NGINX_IMAGE_NAME):$(NGINX_IMAGE_TAG)
	docker push $(APP_IMAGE_NAME):$(APP_IMAGE_TAG)

deploy:
	cd terraform; terraform init
	cd terraform; terraform apply -auto-approve \
	-var nginx_image_name=$(NGINX_IMAGE_NAME) \
	-var nginx_image_tag=$(NGINX_IMAGE_TAG) \
	-var app_image_name=$(APP_IMAGE_NAME) \
	-var app_image_tag=$(APP_IMAGE_TAG)
