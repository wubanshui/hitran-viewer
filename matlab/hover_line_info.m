function hover_line_info(fig)
% HOVER_LINE_INFO  为 hitran-viewer 主窗口注册鼠标悬停提示
%   鼠标在光谱图或棒状图上移动时，自动吸附到最近的吸收线，
%   并以浮动标签显示该线的参数（波数、波长、线强、量子标识等）。
%   谱线数据来自 axStick.UserData（由 plot_spectrum 写入）。

    set(fig, 'WindowButtonMotionFcn', @onMotion);
end

function onMotion(fig, ~)
    app = fig.UserData;
    if ~isstruct(app) || ~isfield(app, 'tip')
        return;
    end
    tip = app.tip;
    axStick = app.axStick;
    axSpec = app.axSpec;

    ud = axStick.UserData;
    if isempty(ud) || ~isstruct(ud)
        tip.Visible = 'off';
        return;
    end

    % 指针所在 figure 像素坐标
    op = fig.CurrentPoint;
    pStick = axStick.Position;
    pSpec = axSpec.Position;
    inStick = op(1) >= pStick(1) && op(1) <= pStick(1) + pStick(3) && ...
              op(2) >= pStick(2) && op(2) <= pStick(2) + pStick(4);
    inSpec  = op(1) >= pSpec(1)  && op(1) <= pSpec(1) + pSpec(3) && ...
              op(2) >= pSpec(2)  && op(2) <= pSpec(2) + pSpec(4);
    if ~inStick && ~inSpec
        tip.Visible = 'off';
        return;
    end

    % 当前指针的数据坐标 -> 波数
    if inStick
        x = axStick.CurrentPoint(1, 1);
        xunit = ud.xunit;
    else
        x = axSpec.CurrentPoint(1, 1);
        xunit = app.ddXUnit.Value;
    end
    if strcmp(xunit, 'nm')
        nu = 1e7 / x;
    else
        nu = x;
    end

    % 吸附到最近谱线
    [d, i] = min(abs(ud.nu - nu));
    span = max(ud.nu) - min(ud.nu);
    tol = max(span / 120, 0.05);   % 吸附容差：跨度的 1/120 或 0.05 cm-1
    if d > tol
        tip.Visible = 'off';
        return;
    end

    tip.Text = ud.info{i};
    tx = min(op(1) + 16, fig.Position(3) - 270);
    ty = min(op(2), fig.Position(4) - 130);
    tip.Position = [tx ty 265 120];
    tip.Visible = 'on';
end
