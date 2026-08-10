# hitran-viewer

面向 TDLAS / 光声光谱激光器选线的气体吸收线可视化工具。

- **后端**：Python Flask 封装官方开源 [HAPI](https://github.com/hitranonline/hapi)（HITRAN Application Programming Interface，MIT 许可），提供谱线数据获取、筛选与光谱计算 REST 接口
- **前端**：MATLAB 原生 GUI（uifigure），通过 HTTP/JSON 与后端通信，绘图与交互全部在 MATLAB 中完成，规避 MATLAB 直接调用 Python 的类型转换与调试困难
- **数据策略**：首次从 HITRANonline 获取数据需联网，之后本地缓存（`.data`/`.header`，与 `.par` 格式兼容）离线可用

## 主要功能

- 在线 fetch HITRAN 谱线数据（支持手动导入 .par/.data 文件兜底）
- 吸收系数 / 透过率 / 吸收谱计算（Voigt、Lorentz、Gaussian、HT 线型，TIPS 配分函数）
- 多曲线叠加对比，评估交叉干扰
- 谱线棒状图，鼠标悬停自动吸附最近吸收线并显示参数（波数、波长、线强、量子标识）
- 仪器函数卷积（sinc/gaussian/rectangular/triangular）
- 波数/波长双单位、PNG/CSV 导出

## 目录结构

```
hitran-viewer/
├── environment.yml        # conda 环境（python 3.11 + flask + hitran-api）
├── start_backend.bat      # 一键启动后端
├── backend/
│   ├── app.py             # Flask REST 服务（默认 http://127.0.0.1:5000）
│   ├── hapi_engine.py     # HAPI 封装层
│   ├── molecules.json     # HITRAN 分子编号与中文名
│   └── settings.template.json  # 配置模板（复制为 settings.json 使用）
├── data/                  # HITRAN 本地缓存（git 忽略）
├── matlab/
│   ├── hitran_gui.m       # 主界面
│   ├── hapi_client.m      # HTTP 客户端
│   ├── plot_spectrum.m    # 光谱/棒状图绘制
│   ├── hover_line_info.m  # 悬停提示
│   ├── export_tools.m     # PNG/CSV 导出
│   ├── test_workflow.m    # 端到端测试
│   └── verify_1653nm.m    # 1653 nm 甲烷验证用例
└── output/                # 导出产物
```

## 快速开始

1. **创建 Python 环境**

   ```
   conda env create -f environment.yml
   ```

   若 pip 步骤因代理失败，可手动补装：

   ```
   conda activate hitran-viewer
   pip install -i https://pypi.tuna.tsinghua.edu.cn/simple flask flask-cors hitran-api
   ```

2. **配置 HITRAN API key（可选但推荐）**

   免费注册 https://hitran.org 账号，在个人主页 https://hitran.org/profile/ 生成 API key；
   复制 `backend/settings.template.json` 为 `backend/settings.json` 填入，或在 MATLAB 界面顶栏点击"连接设置"配置。
   （官方文档注明下载数据需要 API key 且有每日请求限额；实测 `/lbl/api` 端点小流量请求无 key 也可用。）

3. **启动后端**：双击 `start_backend.bat`（或 `python backend/app.py`）

4. **启动界面**：MATLAB 中执行

   ```matlab
   cd hitran-viewer/matlab
   hitran_gui
   ```

## 选线工作流示例（1653 nm 甲烷）

1. 界面中选择 CH4（同位素 1），波数范围 6040–6060 cm⁻¹，点击"Fetch 下载"
2. 同样方法下载干扰气体（H2O、CO2、NH3、C2H2 等）
3. 设置温度 296 K、压力 1 atm、光程与浓度，选择"吸收系数"，点击"计算并绘图"
4. 切换不同气体表重复计算，曲线自动叠加对比
5. 点击"显示谱线"绘制棒状图，鼠标悬停查看任意吸收线参数
6. 导出 PNG/CSV

验证脚本 `matlab/verify_1653nm.m` 给出的参考结果：目标线 6046.9636 cm⁻¹（1653.72 nm），S = 1.43e-21。

## 后端 REST 接口

| 接口 | 方法 | 说明 |
|---|---|---|
| `/api/health` | GET | 连接测试 |
| `/api/molecules` | GET | 分子列表 |
| `/api/isotopologues/<M>` | GET | 分子 M 的同位素列表 |
| `/api/tables` | GET | 本地数据表 |
| `/api/fetch` | POST | 在线下载谱线 `{table,M,I,numin,numax}` |
| `/api/import` | POST | 导入 .par/.data `{path,table}` |
| `/api/lines/<table>` | GET | 谱线参数（可带 `numin`/`numax`/`limit`） |
| `/api/spectrum` | POST | 光谱计算（组分、T、p、光程、浓度、线型、步长、仪器卷积） |
| `/api/settings` | GET/POST | 读写配置（API key 等） |

## 常见问题

- **MATLAB 连接后端报 CURLE 52 / Empty reply**：本机代理软件拦截了回环流量，请确认环境变量 `NO_PROXY=127.0.0.1,localhost`（安装时已自动写入用户环境变量）。
- **fetch 报 403**：API key 无效或超出每日限额，稍后再试或更换 key。
- **fetch 报 404**：该分子在所选波段没有 HITRAN 逐线数据（例如 C2H6 在 6030–6070 cm⁻¹）。
- **pip 安装报 Missing dependencies for SOCKS support**：代理环境变量与 pip 冲突，参照"快速开始"第 1 步手动安装。

## 引用

本工具基于 HAPI，如在研究中使用请引用：

> R.V. Kochanov, I.E. Gordon, L.S. Rothman, P. Wcislo, C. Hill, J.S. Wilzewski, "HITRAN Application Programming Interface (HAPI): A comprehensive approach to working with spectroscopic data", J. Quant. Spectrosc. Radiat. Transfer 177, 15-30 (2016)

## 许可

MIT License
