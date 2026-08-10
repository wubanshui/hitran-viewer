function export_tools(action, app)
% EXPORT_TOOLS  hitran-viewer 导出工具
%   export_tools('png', app)   将当前界面导出为 PNG（300 dpi）
%   export_tools('csv', app)   导出最近一条曲线的数值数据（CSV）
%
%   app 为 hitran_gui 的应用状态 struct（含 fig、curves 字段）。

    switch lower(action)
        case 'png'
            exportPng(app);
        case 'csv'
            exportCsv(app);
        otherwise
            error('export_tools:badAction', '未知操作: %s', action);
    end
end

function exportPng(app)
    [fn, fp] = uiputfile({'*.png', 'PNG 图片 (*.png)'}, '导出 PNG', ...
        'spectrum.png');
    if isequal(fn, 0), return; end
    exportgraphics(app.fig, fullfile(fp, fn), 'Resolution', 300);
    notify(app, ['已导出 ' fn]);
end

function exportCsv(app)
    if isempty(app.curves)
        uialert(app.fig, '暂无曲线数据', '提示');
        return;
    end
    [fn, fp] = uiputfile({'*.csv', 'CSV 文件 (*.csv)'}, '导出 CSV', ...
        'spectrum.csv');
    if isequal(fn, 0), return; end
    c = app.curves{end};
    T = table(c.wn(:), 1e7 ./ c.wn(:), c.y(:), ...
        'VariableNames', {'wavenumber_cm1', 'wavelength_nm', 'value'});
    writetable(T, fullfile(fp, fn));
    notify(app, ['已导出 ' fn]);
end

function notify(app, msg)
    % 顶栏状态栏提示（避免依赖高版本才有的 uitoast）
    app.lblStatus.Text = msg;
    app.lblStatus.FontColor = [0.1 0.5 0.1];
end
