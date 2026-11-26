# BreederTron3000 开发说明

## 在游戏中安装测试分支

提交改动并将 `test` 分支推送到 GitHub，然后在运行 OpenOS 的 OC 电脑上安装测试版。

```sh
wget -f https://gh-proxy.org/https://raw.githubusercontent.com/QwQe308/GTNH_BEE_AUTO_BREED/test/BreederTron3000/setup.lua setup.lua && setup test
```

需要测试机器人脚本时，在机器人使用的 OpenOS 系统中运行以下命令。

```sh
wget -f https://gh-proxy.org/https://raw.githubusercontent.com/QwQe308/GTNH_BEE_AUTO_BREED/test/BreederTron3000/robotSetup.lua robotSetup.lua && robotSetup test
```

`setup` 和 `robotSetup` 的第一个参数指定要下载脚本的分支，省略时使用 `main`。测试完成后，运行 `setup` 或 `robotSetup` 即可切回正式版。`test` 合并到 `main` 时无需修改安装器的默认值。
