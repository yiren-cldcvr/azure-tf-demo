# Azure TF Demo

## Prerequisite

1. First build docker image inside `app` folder
```
docker build . -t <hub-user>/<repo-name>[:<tag>]
```


2. Push the docker image
```
docker push <hub-user>/<repo-name>[:<tag>]
```

3. Alternatively you can use existing docker image `yicldcvr/azure-demo:latest`

3. Create a `terraform.tfvars` and fill in the values
```
name          = <prefix for resources>
location      = <location>
address_space = [<virtual network CIDR>]
address_prefixes = {
  "web" = [<web subnet CIDR>],
  "app" = [<app subnet CIDR>],
  "db"  = [<db subnet CIDR>]
}
user     = <username for db>
password = <password for db>
docker_image = <hub-user>/<repo-name>[:<tag>] #Put "yicldcvr/azure-demo:latest" if you didn't build it
```

4. Run `terraform init` then `terraform apply`, accept the prompt to proceed after verifying the changes.

