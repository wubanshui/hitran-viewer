# MATLAB MCP Server 注册说明

本项目开发/调试可通过 MathWorks 官方 MATLAB MCP Server 由 AI 助手直接驱动 MATLAB。

## 已就绪

- 二进制已下载并验证：`C:\tools\matlab-mcp\matlab-mcp-server.exe`（v0.11.3，github.com/matlab/matlab-mcp-server）
- MATLAB R2025a 已安装并在系统 PATH（`D:\matlab\2025a\bin\matlab.exe`），满足 R2020b+ 要求

## 在 MCP 客户端中注册

在 IDE/客户端的 MCP 配置中添加（stdio 传输）：

```json
{
  "mcpServers": {
    "matlab": {
      "command": "C:\\tools\\matlab-mcp\\matlab-mcp-server.exe"
    }
  }
}
```

注册后可用能力：启动/退出 MATLAB、执行 MATLAB 代码、代码风格与正确性检查。

## 验证方法

注册完成后，让助手执行：

```matlab
disp(version)
cd('c:\Users\26587\Documents\QoderCN\2026-08-10\chat-1\hitran-viewer\matlab')
test_workflow
```

若 `test_workflow` 全部通过（需后端已启动），说明 MCP 链路正常。

## 备选：批处理模式

未注册 MCP 时也可直接命令行驱动 MATLAB（本项目验证即采用此方式）：

```bat
matlab -batch "cd('...\hitran-viewer\matlab'); test_workflow"
```

注意：本机代理环境下需存在用户环境变量 `NO_PROXY=127.0.0.1,localhost`（安装时已写入），
否则 MATLAB 访问本地后端会报 CURLE 52。
