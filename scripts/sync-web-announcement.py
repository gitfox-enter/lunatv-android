"""Sync the web announcement wording with the app's NoticeDialog text.

Done with regex so the escaped \\n sequences (literal backslash-n in the TS
source, not real newlines) are matched without hand-escaping.
"""
import pathlib
import re

FILES = [
    'src/app/layout.tsx',
    'src/components/SiteProvider.tsx',
    'src/lib/config.ts',
]

# 匹配以 '本网站仅提供影视信息... 开头、以 邀请码：AXWJBV8' 结尾的单引号字符串，
# 内部允许任何字符（含字面量 \n 两个字符）。
PATTERN = re.compile(
    r"'本网站仅提供影视信息搜索服务.*?邀请码：AXWJBV8'",
    re.DOTALL,
)

NEW = (
    "'本应用仅提供影视信息搜索服务，所有内容均来自第三方网站。"
    "本应用不存储任何视频资源，不对内容的准确性、合法性、完整性负责。"
    "\\n\\n"
    "这是个人出于兴趣开发的学习项目，作者能力有限，后续不再维护更新。"
    "使用中如遇到问题，请先尝试自行解决。"
    "\\n\\n"
    "另外：最近在用一个 AI 办公工具 DuMate，处理文档和杂事挺省时间。"
    "通过下面的邀请链接注册，双方各得 2000 积分。"
    "\\nhttps://www.dumate.cn/?track=yqyl"
    "\\n邀请码：AXWJBV8'"
)

for f in FILES:
    p = pathlib.Path(f)
    t = p.read_text(encoding='utf-8')
    m = PATTERN.search(t)
    if not m:
        print(f'未匹配: {f}')
        continue
    t2 = t[:m.start()] + NEW + t[m.end():]
    p.write_text(t2, encoding='utf-8')
    print(f'OK {f}  (替换 {m.end() - m.start()} 字符)')