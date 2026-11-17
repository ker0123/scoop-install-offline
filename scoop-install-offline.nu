use std/log

def main [] {
    "
快捷地导出 scoop 本地安装的软件, 用以导入到离线环境下的电脑

    export - 导出. 先创建 list.toml, 待用户修改保留需要迁移的软件后, 下一次运行真正执行导出
    import - 导入. 需要准备好 buckets / apps. 会在当前目录自动查询, 解包然后安装
    "
}

def "main export" [] {
    cd ($env.FILE_PWD? | default '.')

    # 第一次运行的时候会产生一个 list.toml, 记录 app list
    if not ('list.toml' | path exists) {
        ^scoop export | from json | to toml | save list.toml
        "软件列表已经保存在 list.toml. 请自行编辑, 留下需要迁移的软件记录"
    } else {
        # 读 list.toml, 组合所有 buckets 的完整路径
        open list.toml | get buckets | each {|r|
            {Name: $r.Name, Path: ([$env.SCOOP, 'buckets', $r.Name] | path join)}
        } | let buckets
        # 打包所有 bucket
        for bucket in $buckets {
            let bundle_name = $"($bucket.Name).bundle"
            log info $"^git -C ($bucket.Path) bundle create ($bundle_name) --all"
            ^git -C $bucket.Path bundle create $bundle_name --all
            [$bucket.Path, $bundle_name] | path join | let bundle_path
            mv $bundle_path .
        }
        ^7z a -mx0 buckets.tar ./*.bundle
        rm ./*.bundle
        # 下载所有安装包
        open list.toml | get apps | each {|app|
            [$app.Name, '@' ,$app.Version] | str join | let app_at_version
        } | let app_at_version_list
        log info $"^scoop download ($app_at_version_list) -u"
        ^scoop download ...$app_at_version_list -u
        # 打包所有要压缩的包
        ls ([$env.SCOOP, 'cache'] | path join) | let scoop_cache
        open list.toml | get apps | each {|app|
            [$app.Name, '#' ,$app.Version] | str join | let app_s_version
            # 在 scoop_cache 里搜索 app#version. 找到的话就补全 path: app#version#hash.ext
            if ($scoop_cache | where name =~ $app_s_version | is-not-empty) {
                $scoop_cache | where name =~ $app_s_version | sort-by modified | last | get name
            }
        } | compact | let packs
        ^7z a -mx0 apps.tar ...$packs

    }
}

def "main import" [] {
    cd ($env.FILE_PWD? | default '.')

    # 解压 buckets
    ^7z x buckets.tar -y
    ls | where name =~ '.bundle' | each {|bundle|
        $bundle.name | path parse | get stem | let repo_name
        [$env.SCOOP, 'buckets', $repo_name] | path join | let repo_path
        if ($repo_path | path exists) {rm -r $repo_path}
        log info $"^git clone ($bundle.name) ($repo_path)"
        ^git clone $bundle.name $repo_path
    }
    rm ./*.bundle

    # 解压 apps
    [$env.SCOOP, 'cache'] | path join | let scoop_cache
    log info $"^7z x apps.tar -o($scoop_cache)"
    ^7z x apps.tar $"-o($scoop_cache)" -y
}
