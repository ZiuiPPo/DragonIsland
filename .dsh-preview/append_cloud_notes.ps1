$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$target = 'D:\MilkyFrogStead\docs\学习笔记.docx'
$backup = 'D:\MilkyFrogStead\.dsh-preview\learning_notes_before_cloud_append.docx'
$heading = '2026年11月8日 云朵浮动效果实现详解'
$z = [IO.Compression.ZipFile]::OpenRead($target)
$r = [IO.StreamReader]::new($z.GetEntry('word/document.xml').Open())
$original = $r.ReadToEnd()
$r.Dispose()
$z.Dispose()
if ($original.Contains($heading)) { throw 'This entry already exists; refusing duplicate append.' }

function Para([string]$text, [string]$kind = 'body', [bool]$pageBreak = $false) {
    $escaped = [Security.SecurityElement]::Escape($text)
    $size = '22'
    $extra = ''
    $runExtra = ''
    if ($kind -eq 'title') { $size = '30'; $extra = '<w:pStyle w:val="Heading1"/><w:keepNext/>'; $runExtra = '<w:b/>' }
    if ($kind -eq 'head') { $size = '24'; $extra = '<w:pStyle w:val="Heading2"/><w:keepNext/>'; $runExtra = '<w:b/>' }
    if ($kind -eq 'code') { $size = '19'; $extra = '<w:keepLines/>'; }
    if ($pageBreak) { $extra += '<w:pageBreakBefore/>' }
    $ascii = if ($kind -eq 'code') { 'Consolas' } else { 'Calibri' }
    return '<w:p><w:pPr>' + $extra + '<w:spacing w:after="120" w:line="300" w:lineRule="auto"/><w:widowControl/></w:pPr><w:r><w:rPr><w:rFonts w:eastAsia="Microsoft YaHei" w:ascii="' + $ascii + '" w:hAnsi="' + $ascii + '"/><w:sz w:val="' + $size + '"/><w:color w:val="000000"/>' + $runExtra + '</w:rPr><w:t xml:space="preserve">' + $escaped + '</w:t></w:r></w:p>'
}

$addition = [Text.StringBuilder]::new()
function Add([string]$text, [string]$kind = 'body', [bool]$pageBreak = $false) {
    [void]$addition.Append((Para $text $kind $pageBreak))
}
Add $heading 'title' $true
Add '问题：游戏里的云朵浮动效果是怎样实现的？怎样让不同云朵自然移动，同时保持内部灰度纹理固定？'
Add '本节补充现有“云影如何跟随世界坐标”和“从参考照片提取柔和云影”，重点解释运动公式与固定纹理。当前效果是二维灰色云影：世界坐标定位，镜头缩放时随地图缩放；此前尝试的固定屏幕尺寸方案已撤回。'
Add '一 脚本与着色器的分工' 'head'
Add 'cloud_layer.gd 每帧累加 elapsed，并把逆画布变换的原点与两个基向量传给 shader。脚本不逐个创建云朵节点；CloudLayer 中的全屏 ColorRect 使用着色器，GPU 为每个片元计算云影强度。云层在 UI 下方，以乘色方式压暗地面。'
Add '二 平移是改变采样位置' 'head'
Add 'p = (world - wind * elapsed - gust) / spacing + noise_offset * 100.0' 'code'
Add 'world 是当前片元对应的世界位置；wind 是每秒位移；spacing 把位置换算为云格子坐标。假设一维图案为 F(x)，F(x-vt) 中同一特征点的位置为 x=x₀+vt，因此减去时间位移会让图案向风向移动，不需要真的移动图片节点。'
Add '例：wind=(12,4)，经过10秒，基础风产生(120,40)世界像素的位移。实际位置还叠加阵风和每朵云的摆动，所以不会所有云都匀速平移。'
Add 'gust = (sin(t*0.065), sin(t*0.043+1.2)) * (45,32)' 'code'
Add 'gust 是平滑变化的位移，两个方向采用不同频率。它改变瞬时移动速度，形成轻微起伏；这不是每帧重新抽随机数，因此不会位置跳闪。'
Add '三 每朵云为什么动得不一样' 'head'
Add 'floor(p) 得到格子编号。hash(id+常量) 生成稳定的伪随机值，决定有无云、六张图中的哪一张、尺寸和初始角度。相同编号在本次运行中得到相同结果。shader 检查当前格子及周围8个格子，让跨格子的云也能被画出来。'
Add '每朵云有独立的 phase 与 rate，摆动采用 sin(t*rate+phase) 和 cos(t*rate*0.71+phase)。当前位移幅度为0.085格，即约49.3世界像素；初始角度为±65°，再叠加±7°的缓慢摆转。'

Add '四 内部纹理如何固定在云朵上' 'head' $true
Add '先用片元与云中心的相对位置除以尺寸，再做逆旋转和图片宽高比换算，得到云自身的局部 UV。整体移动、旋转时，同一个轮廓位置仍对应同一个局部 UV。噪波读取这个局部坐标，就像印在云朵上。'
Add 'flow = uv * 1.9 + id * 0.37' 'code'
Add 'n = texture(noise_tex, flow).r' 'code'
Add 'fine = texture(noise_tex, flow * 3.1).r' 'code'
Add 'density = mix(0.42, 1.0, smoothstep(0.25, 0.75, n*0.65 + fine*0.35))' 'code'
Add '两种尺度的噪波组成固定浓淡，id 让不同云取到不同区域。这里没有 elapsed；如果再往 flow 里加入时间偏移，纹理就会在云内部自行流动，出现之前不希望看到的变化。边缘扰动也读取这套固定噪波。'
Add '五 从轮廓到最终阴影' 'head'
Add '原图先通过颜色阈值提取遮罩，再以5×5加权采样近似高斯模糊。遮罩与 density 相乘，得到云影强度；多朵云重叠时当前代码取最大值，不是把阴影逐层相加。模糊和阈值的基础说明见前面的云影章节。'
Add 'factor = mix(白色, 灰色, mask * 0.24)' 'code'
Add 'blend_mul 将底图乘以 factor：白色系数不改变底图，较暗系数压暗底图。0.24是当前强度参数；调低会使整朵云更淡。它在 shader 中参与乘色系数计算，最终输出 alpha 仍为1。'
Add '六 调整参数与易错点' 'head'
Add '当前默认值：spacing=580；coverage=0.55；size_range=(180,540)，即基础尺寸的1～3倍；wind=(12,4)；pixel_size=4；edge_blur=0.04；edge_noise=0.018。coverage 控制格子生成云的概率，并不代表屏幕有55%的面积被覆盖。'
Add '运动用时间，内部灰度不用时间。每帧重抽随机数会闪烁；仅用屏幕坐标采样会让云贴着屏幕。pixel_size 是世界网格尺寸，不等于减少 GPU 片元数量；25次模糊采样及邻格遍历仍有开销。'
Add '代码位置（相对工程目录 milky-frog-stead）：scripts/world/cloud_layer.gd 负责时间与坐标；shaders/clouds.gdshader 负责分布、运动、灰度和合成；scenes/farm/cloud_layer.tscn 负责挂载材质与纹理。'
Add '练习：希望云移动更快，但内部图案不变，应改哪里？答案：调整 wind；若要加快摆动，可调整 rate。不要给 flow 加时间，也不要每帧重置 noise_offset。'

# Insert only new paragraphs before the final section properties. Preserve all original XML bytes.
$match = [regex]::Matches($original, '<w:sectPr(?:\s|>)')
if ($match.Count -eq 0) { throw 'Missing final section properties' }
$index = $match[$match.Count - 1].Index
$updated = $original.Insert($index, $addition.ToString())
[xml]$parsed = $updated
Copy-Item -LiteralPath $target -Destination $backup
$archive = [IO.Compression.ZipFile]::Open($target, [IO.Compression.ZipArchiveMode]::Update)
try {
    $entry = $archive.GetEntry('word/document.xml')
    $entry.Delete()
    $entry = $archive.CreateEntry('word/document.xml')
    $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
    $writer.Write($updated)
    $writer.Dispose()
} finally { $archive.Dispose() }
# Validate content retention and byte-equivalence of every other ZIP member.
$before = [IO.Compression.ZipFile]::OpenRead($backup)
$after = [IO.Compression.ZipFile]::OpenRead($target)
try {
    foreach ($entry in $before.Entries) {
        if ($entry.FullName -eq 'word/document.xml') { continue }
        $other = $after.GetEntry($entry.FullName)
        if ($null -eq $other) { throw ('Lost entry: ' + $entry.FullName) }
        $a = [IO.MemoryStream]::new(); $b = [IO.MemoryStream]::new()
        $sa = $entry.Open(); $sb = $other.Open()
        $sa.CopyTo($a); $sb.CopyTo($b); $sa.Dispose(); $sb.Dispose()
        if ([Convert]::ToBase64String($a.ToArray()) -cne [Convert]::ToBase64String($b.ToArray())) { throw ('Changed entry: ' + $entry.FullName) }
        $a.Dispose(); $b.Dispose()
    }
    if ($updated.Remove($index, $addition.Length) -cne $original) { throw 'Original body changed' }
    $reader = [IO.StreamReader]::new($after.GetEntry('word/document.xml').Open())
    $saved = $reader.ReadToEnd(); $reader.Dispose()
    if ($saved -cne $updated) { throw 'Saved content mismatch' }
    Write-Output 'PASS: appended cloud implementation notes; original content and all other package entries preserved.'
} finally { $before.Dispose(); $after.Dispose() }
