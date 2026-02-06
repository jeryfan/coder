# Terraform Docker Build 教程中文整理（含重点讲解与示例）

**概览**
本文基于 HashiCorp 官方的 Docker Build 教程内容进行中文整理，目标是用 Terraform 拉取 Nginx 镜像并启动容器，把容器的 80 端口映射到本机 8000 端口，然后通过浏览器验证结果。

**前置条件**
- 已安装 Terraform CLI（官方教程要求 0.15+）。
- 已安装并启动 Docker。

**创建目录与文件**
在任意工作目录下新建项目文件夹并创建 `main.tf`：

```bash
mkdir learn-terraform-docker-container
cd learn-terraform-docker-container
touch main.tf
```

**最小可运行配置（与教程等价）**
下面是与官方教程等价的 `main.tf` 示例，加入了少量中文注释以便理解：

```hcl
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {
  # Windows 示例：
  # host = "npipe:////.//pipe//docker_engine"
}

resource "docker_image" "nginx" {
  name         = "nginx:latest"
  keep_locally = false
}

resource "docker_container" "nginx" {
  name  = "tutorial"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 8000
  }
}
```

**重点讲解**
1. `terraform` 块：用 `required_providers` 声明所需的 provider 来源与版本约束。`source` 是 provider 地址（形如 `namespace/type` 或带 registry hostname 的全地址），`version` 建议固定范围以避免不兼容升级。
2. `provider` 块：这里配置 Docker provider 的连接方式。大多数本地环境可留空；Windows 需用 `npipe` 连接 Docker Engine。
3. `resource` 块：`resource "TYPE" "NAME"` 组合形成唯一资源地址，例如 `docker_image.nginx`。在同一配置中可以引用 `resource` 的属性（如 `image_id`）。
4. `docker_image` 与 `docker_container`：容器资源通过 `image = docker_image.nginx.image_id` 关联镜像资源；`ports` 块把容器内 80 端口映射到宿主机 8000 端口。

**命令流程**
常见的执行顺序如下（教程里会直接执行 `terraform apply`，这里补充了推荐步骤）：

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

- `terraform init`：初始化工作目录、下载 provider，并生成锁定文件（`.terraform.lock.hcl`）。
- `terraform fmt`：按官方格式规范化配置文件。
- `terraform validate`：做语法与内部一致性检查。
- `terraform plan`：生成执行计划，预览即将发生的变更。
- `terraform apply`：执行变更，通常会提示输入 `yes` 确认。

**创建并验证基础设施**
执行 `terraform apply` 后，如果一切正常，会创建镜像与容器。随后访问 `http://localhost:8000` 就能看到 Nginx 默认页面。

**状态与检查**
- Terraform 会维护 `terraform.tfstate` 状态文件来追踪资源绑定关系与属性。
- `terraform show` 可查看当前状态的可读输出。
- `terraform state list` 可列出当前配置下的所有资源地址。

**练习：修改端口（举例）**
官方下一步教程示例会把外部端口从 8000 改为 8080。你可以把 `ports` 的 `external` 改成 8080，再执行 `terraform plan` 与 `terraform apply`，然后访问 `http://localhost:8080`。

**小结**
到这里，你已经掌握了用 Terraform 管理 Docker 镜像与容器的最小闭环：编写配置、初始化、校验、执行、验证与查看状态。
