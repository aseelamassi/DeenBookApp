#requires -Version 5.1
<#
Run from the extracted Flutter project:
  .\Start-DeenBook.ps1 -CheckOnly
  .\Start-DeenBook.ps1 -SupportPhone '+970...'
Use the real international administration number, not the example above.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'https://api-deenbook.runasp.net',
    [string]$SupportPhone = '',
    [string]$Device = '',
    [switch]$CheckOnly
)

function Resolve-DeenBookBaseUrl {
    param([string]$Value)
    $address = $null
    if (-not [Uri]::TryCreate($Value.Trim(), [UriKind]::Absolute, [ref]$address) -or
        $address.Scheme -ne 'https' -or [string]::IsNullOrEmpty($address.Host) -or
        $address.UserInfo -ne '' -or $address.Query -ne '' -or $address.Fragment -ne '') {
        throw 'رابط الخادم يجب أن يبدأ بـ https:// وبدون بيانات دخول أو معاملات إضافية.'
    }
    $builder = New-Object System.UriBuilder($address)
    $builder.Path = $address.AbsolutePath.TrimEnd('/') -replace '(?i)/api\.?$', ''
    return $builder.Uri.AbsoluteUri.TrimEnd('/')
}

function Resolve-DeenBookSupportPhone {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $number = $Value.Trim() -replace '[\s()+-]', ''
    if ($number.StartsWith('00')) { $number = $number.Substring(2) }
    if ($number -cnotmatch '^[1-9][0-9]{8,14}$') {
        throw 'رقم الإدارة غير صالح. استخدم الرقم الدولي الحقيقي مع رمز البلد، بدون X أو أحرف.'
    }
    return $number
}

function Get-DeenBookHttpStatus {
    param([string]$Url)
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    $client.DefaultRequestHeaders.Accept.ParseAdd('application/json')
    $response = $null
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        # Windows PowerShell 5.1 may otherwise inherit an older TLS default.
        if ($PSVersionTable.PSVersion.Major -le 5) {
            [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
        $response = $client.GetAsync($Url, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        return [int]$response.StatusCode
    }
    catch {
        throw 'تعذّر الاتصال الآمن بالخادم أو انتهت المهلة. راجع تفعيل HTTPS والشهادة وإمكانية الوصول إلى الاستضافة.'
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
        $handler.Dispose()
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

function Assert-DeenBookConnection {
    param([string]$Url)
    $status = Get-DeenBookHttpStatus -Url ($Url + '/api/subscription/plans')
    if ($status -eq 401) {
        Write-Host 'اتصال HTTPS يعمل، ومسار الخطط يطلب تسجيل الدخول (401)، وهذه النتيجة متوقعة.' -ForegroundColor Green
        Write-Host 'هذا فحص وصول فقط؛ لا يتحقق من الحساب أو قاعدة البيانات أو الاشتراك.'
        return
    }
    if ($status -ge 300 -and $status -lt 400) {
        throw "الخادم يحوّل الطلب إلى عنوان آخر (HTTP $status). اضبط BaseUrl على عنوان API النهائي."
    }
    if ($status -eq 404) {
        throw 'مسار API غير موجود (404). تحقق من نشر مشروع DeenBook.Api ومن رابط المضيف.'
    }
    if ($status -ge 500) {
        throw "الخادم أو بوابة الاستضافة غير متاحين (HTTP $status). راجع HTTPS وسجل أخطاء الاستضافة."
    }
    if ($status -eq 403 -or $status -eq 429) {
        throw "الخادم يرفض الفحص أو يقيّد الطلبات (HTTP $status). راجع إعدادات الوصول أو أعد المحاولة لاحقاً."
    }
    throw "رد غير متوقع من مسار الخطط (HTTP $status). تحقق أن الرابط يشير إلى DeenBook.Api."
}

function Invoke-DeenBookStart {
    param(
        [string]$Url,
        [string]$Phone,
        [string]$TargetDevice,
        [string]$ProjectDirectory,
        [switch]$OnlyCheck
    )
    $normalizedUrl = Resolve-DeenBookBaseUrl -Value $Url
    $normalizedPhone = Resolve-DeenBookSupportPhone -Value $Phone
    Write-Host "API: $normalizedUrl"
    Assert-DeenBookConnection -Url $normalizedUrl
    if ($normalizedPhone -eq '') {
        Write-Warning 'رقم إدارة الاشتراكات غير محدد. سيظهر الطلب للنسخ فقط؛ لن يفتح التطبيق محادثة واتساب.'
    }
    if ($OnlyCheck) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectDirectory 'pubspec.yaml') -PathType Leaf)) {
        throw 'ضع هذا الملف داخل مجلد مشروع Flutter الذي يحتوي على pubspec.yaml.'
    }
    $flutterCommand = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $flutterCommand) {
        throw 'Flutter غير موجود في PATH. ثبّته، وأضف flutter\bin إلى PATH ثم افتح PowerShell من جديد.'
    }
    Push-Location -LiteralPath $ProjectDirectory
    try {
        & $flutterCommand.Source pub get
        if ($LASTEXITCODE -ne 0) { throw 'فشل flutter pub get. راجع الرسالة السابقة قبل إعادة التشغيل.' }
        $flutterArguments = @('run', "--dart-define=API_BASE_URL=$normalizedUrl", "--dart-define=SUPPORT_PHONE=$normalizedPhone")
        if (-not [string]::IsNullOrWhiteSpace($TargetDevice)) { $flutterArguments += @('-d', $TargetDevice) }
        & $flutterCommand.Source @flutterArguments
        if ($LASTEXITCODE -ne 0) { throw 'توقف Flutter بخطأ. راجع رسالته أعلاه؛ نجاح فحص الخادم لا يضمن نجاح بناء التطبيق.' }
    }
    finally { Pop-Location }
}

# Dot-sourcing loads the functions without probing the network or starting Flutter.
if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    try {
        Invoke-DeenBookStart -Url $BaseUrl -Phone $SupportPhone -TargetDevice $Device -ProjectDirectory $PSScriptRoot -OnlyCheck:$CheckOnly
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}
