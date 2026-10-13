# Security Audit

审计对象：`slobys/xboard-one-click` 当前 `main` 分支，以及它默认拉取的 `cedar2025/Xboard` `compose` 分支。

审计时间：2026-10-13。

## 结论

在公开仓库的 shell 脚本、Compose 模板和提交历史中，没有发现明显的反弹 shell、隐藏定时任务、凭据窃取或可疑第三方下载链。

但原项目存在供应链和权限风险，不能把“没有看到木马”当作“部署绝对安全”。本副本已做以下加固：

- `deploy.env` 改为白名单键值解析，不再执行任意 shell 语句。
- Xboard 源码默认固定到已审计提交 `0a749681bb10056bd60ebe9afe4e8928ff19210c`。
- Xboard 和 Nginx Proxy Manager 镜像固定到 manifest digest，不再使用 `latest`。
- Xboard 端口和固定镜像通过 `compose.override.yaml` 注入，避免修改上游文件。
- 防火墙自动放行默认关闭；全网来源必须显式二次确认。
- 更新流程不再把已有 checkout 重置到浮动远程分支。

## 发现与处置

| 风险 | 原行为 | 处置 |
| --- | --- | --- |
| 高 | `deploy.env` 直接被 shell `source` | 改为白名单解析 |
| 高 | Xboard 和 NPM 使用浮动版本 | 固定源码提交和镜像 digest |
| 中 | 防火墙默认可放行，云来源默认为 `0.0.0.0/0` | 默认关闭，并要求显式确认公网来源 |
| 中 | 更新对源码目录执行 `reset --hard` | 更新到明确提交并 detached checkout |
| 低 | 通过公网 IP 服务探测服务器地址 | 保留功能；可通过 `SERVER_IP` 覆盖 |

## 信任边界

本项目仍然会运行 Docker 镜像中的 Xboard 应用。镜像是预构建二进制，脚本仓库审计不能证明镜像内部每一行代码都安全。更新镜像 digest 前，应重新检查上游源码、镜像来源、构建记录和运行时网络连接。

另外，`bootstrap.sh` 本身通过 HTTPS 拉取 Git 仓库；最高保障方式是先下载并审阅它，或从已验证的提交/发布包开始，而不是直接执行未经审阅的网络脚本。

## 发布前检查

```bash
./tests/test_scripts.sh
bash -n ./*.sh lib/*.sh
rg -n 'latest|source .*deploy\.env|\. .*deploy\.env|reset --hard' . --glob '!docs/**'
```
