# Armbian-install-LNMP
#### 介绍
**脚本可在debian12内网服务器使用，数据库MariaDB**

#### 软件架构
理论上只要是Linux都可尝试使用

### 一键使用
```
bash <(curl -sSL https://zyhqwq.github.io/Armbian-install-LNMP/in.sh)
```

### 一键卸载
```
bash <(curl -sSL https://zyhqwq.github.io/Armbian-install-LNMP/un.sh)
```

#### 安装教程
##### 安装 git
```
sudo apt update && sudo apt install git -y
```
##### 克隆仓库
```
git clone https://github.com/zyhqwq/Armbian-install-LNMP.git
```
##### 进入仓库目录
```
cd install-typecho-on-armbian
```
##### 赋予脚本执行权限
```
chmod +x LNMP.sh
```
##### 以 root 权限执行脚本（根据脚本设计选择是否需要 sudo）
```
sudo ./LNMP.sh
```

#### 使用说明

**学习使用不可用于违法用途，使用deepseek生成，用于分享**
