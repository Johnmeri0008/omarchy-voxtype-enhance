# 商店审核注意事项（Marketplace Review Notes）

> 2026-08-22 整理。来源：本插件 issue
> [#1428](https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/1428)
> 及兄弟插件 #1468、#1401 的审核往返。供上架前自查与复审对照。

## 一、商店审核机制速览

1. **按精确 HEAD 审核**：修复必须上游提交 → issue 评论附 commit 链接 → 按新 HEAD 复审。
2. **自动化基线**：本仓因 `systemctl --user restart voxtype.service` 被标
   **service-management 能力、review-required**。这不是拒绝；README 里说明用途即可，
   但每次改动基线都会重新列出行号，README 与代码必须同步。
3. **人工复审**只盯供应链完整性与资源/注入边界，精确到 `文件:行号`。

## 二、审核人在意的点（从三单反馈提炼）

| # | 关注点 | 出处 | 判例 |
|---|--------|------|------|
| 1 | 供应链固定：不执行下载物、pin immutable 来源 | #1468 | moving-HEAD → root 构建被打回 |
| 2 | TOCTOU：校验与特权使用之间不得隔用户可写状态 | #1468 | make in user cache 被打回 |
| 3 | **资源无界：下载必须按声明大小截断，先限界后校验** | **#1428 本仓判例** | 「downloads until EOF…unbounded disk space」 |
| 4 | 注入面：外部数据 PlainText 渲染、命令列表传参 | #1401 | AutoText 富文本注入 |
| 5 | 提权纪律：**固定内联命令 + 用户显式触发** | #1428 ONNX | `pkexec voxtype setup onnx --enable` 固定串通过；取消不动现状 |
| 6 | 卸载卫生：不留悬挂钩子 | 提交清单 | explicit consent 条款 |
| 7 | 带回归测试的修复被接受最快 | #1428 修复评论 | 「all 7 bridge tests pass」被写进回复 |

## 三、本仓库反馈与修复状态

| 轮次 | 审核意见 | 修复 |
|------|----------|------|
| 1 | 模型下载读到 EOF 才校验大小/哈希，超大响应可耗尽磁盘 | `94b7dd9`：最多多读 1 字节，超限立即失败 + 回归测试 |
| 2（主动加固） | — | `7e41fe8`：下载前检测 ONNX 引擎可用性；ONNX 启用走用户显式触发的固定命令 `pkexec voxtype setup onnx --enable` |

HEAD 即 `6bf0803`。`6bf0803` 新增第二处提权：voxtype 二进制缺失时，变更类入口先经
固定命令 `pkexec pacman -S --noconfirm --needed voxtype-bin` 提供安装（取消即不动，
只读查询不触发）。README 已改为「两处提权、均为固定命令」，并在 #1428 补披露评论。

## 四、本仓库对照自查要点（侦察发现，复审重点）

- [x] 模型下载：pinned HuggingFace URL + SHA-256/大小双校验 + 尺寸上限（判例修复已落地）
- [x] 特权面两处固定命令（`pkexec voxtype setup onnx --enable`；
      `pkexec pacman -S --noconfirm --needed voxtype-bin`），均用户显式触发、列表传参
- [x] 外部命令全部列表参数，无 shell 拼接；engine 切换委托 voxtype CLI 并回读验证
- [x] tests/ 7 个用例可跑（修复评论里引用过，是加分项，保持绿色）
- [ ] **卸载卫生**：universal paste 模式把 `pre/post_output_command`（指向本插件脚本的
      绝对路径）写进用户 `~/.config/voxtype/config.toml`，插件移除后钩子残留、指向已删除路径。
      审核清单的 explicit consent 条款会盯这个；建议提供 clear 动作并在 README 卸载节写明。
- [ ] hyprctl dispatch 表达式为字符串拼接（当前是常量，安全）；保持常量或改列表传参，
      别让未来改动引入插值。
- [ ] 硬编码 UID 路径回退（`/home/<uid>/…` 形态）——换成 `$HOME`/`Path.home()`。
- [ ] 每次写配置都 `systemctl --user restart voxtype.service`：基线已标记此能力，
      README 需解释为何必须重启（voxtype 不热载配置）。
