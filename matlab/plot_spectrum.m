function plot_spectrum(axSpec, axStick, wn, vals, label, xunit, lines)
% PLOT_SPECTRUM  绘制光谱曲线与谱线棒状图
%   plot_spectrum(axSpec, axStick, wn, vals, label, xunit)
%       在 axSpec 上追加一条光谱曲线（hold on）
%   plot_spectrum([], axStick, [], [], '', 'cm-1', lines)
%       仅绘制棒状图（lines 为后端 /api/lines 返回的 struct 数组）
%
%   棒状图数据同时写入 axStick.UserData，供 hover_line_info 悬停查询。

    if nargin < 6, xunit = 'cm-1'; end

    % ---------------- 光谱曲线 ----------------
    if ~isempty(axSpec) && ~isempty(wn)
        hold(axSpec, 'on');
        if strcmp(xunit, 'nm')
            plot(axSpec, 1e7 ./ wn, vals, 'LineWidth', 1.2, ...
                'DisplayName', label);
        else
            plot(axSpec, wn, vals, 'LineWidth', 1.2, ...
                'DisplayName', label);
        end
        grid(axSpec, 'on');
    end

    % ---------------- 棒状图 ----------------
    if ~isempty(axStick) && ~isempty(lines)
        cla(axStick);
        nu = [lines.nu];
        sw = [lines.sw];
        if strcmp(xunit, 'nm')
            x = 1e7 ./ nu;
            stem(axStick, x, sw, 'b', 'Marker', 'none', 'LineWidth', 0.8);
            set(axStick, 'XDir', 'reverse');
            xlabel(axStick, '波长 nm');
        else
            stem(axStick, nu, sw, 'b', 'Marker', 'none', 'LineWidth', 0.8);
            xlabel(axStick, '波数 cm^{-1}');
        end
        ylabel(axStick, '线强 S (cm^-1/(molecule·cm^-2))');
        set(axStick, 'YScale', 'log');

        % 预生成悬停信息字符串
        info = cell(1, numel(lines));
        for k = 1:numel(lines)
            ln = lines(k);
            info{k} = sprintf([...
                '%s 同位素%d\n' ...
                '波数: %.6f cm^-1\n' ...
                '波长: %.2f nm\n' ...
                '线强S: %.3e\n' ...
                'gamma_air: %.4f  E_low: %.1f\n' ...
                '上态: %s\n下态: %s'], ...
                char(ln.molecule), ln.isotopologue, ...
                ln.nu, ln.wl_nm, ln.sw, ...
                nanIfEmpty(ln.gamma_air), nanIfEmpty(ln.elower), ...
                strOrDash(ln.global_upper), strOrDash(ln.global_lower));
        end
        axStick.UserData = struct('nu', {nu}, 'sw', {sw}, ...
            'info', {info}, 'lines', {lines}, 'xunit', xunit);
    end
end

function v = nanIfEmpty(v)
    if isempty(v), v = NaN; end
end

function s = strOrDash(s)
    if isempty(s), s = '-'; end
    s = strtrim(char(s));
    if isempty(s), s = '-'; end
end
