param(
  [int]$NPatients = 8000,
  [int]$Seed = 42,
  [string]$OutputDir = "C:\Users\megan\Documents\RWE\synthetic_rwe_data"
)

if ($NPatients -lt 5000 -or $NPatients -gt 20000) {
  throw "NPatients must be between 5000 and 20000."
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Pick-One {
  param([array]$Values, [double[]]$Weights)
  $x = Get-Random -Minimum 0.0 -Maximum 1.0
  $cum = 0.0
  for ($i = 0; $i -lt $Values.Count; $i++) {
    $cum += $Weights[$i]
    if ($x -le $cum) { return $Values[$i] }
  }
  return $Values[$Values.Count - 1]
}

function Random-Date {
  param([datetime]$Start, [datetime]$End)
  $range = ($End - $Start).Days
  return $Start.AddDays((Get-Random -Minimum 0 -Maximum ($range + 1)))
}

function Maybe-Null {
  param([object]$Value, [double]$MissingRate)
  if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $MissingRate) { return $null }
  return $Value
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$sexVals = @("F", "M")
$sexW = @(0.52, 0.48)
$raceVals = @("White", "Black", "Hispanic", "Asian", "Other", "Unknown")
$raceW = @(0.52, 0.16, 0.14, 0.08, 0.06, 0.04)
$geoVals = @("Northeast", "Midwest", "South", "West")
$geoW = @(0.20, 0.24, 0.36, 0.20)
$insVals = @("Commercial", "Medicare", "Medicaid", "Uninsured", "Other")
$insW = @(0.36, 0.42, 0.14, 0.04, 0.04)

$tumorVals = @("NSCLC", "CRC", "Breast", "Melanoma", "Prostate")
$tumorW = @(0.28, 0.22, 0.22, 0.12, 0.16)
$stageVals = @("I", "II", "III", "IV")
$stageW = @(0.12, 0.20, 0.30, 0.38)
$gradeVals = @("Low", "Intermediate", "High", "Unknown")
$gradeW = @(0.22, 0.37, 0.31, 0.10)
$histVals = @("Adenocarcinoma", "Squamous", "Ductal", "Serous", "Mixed", "Other")
$histW = @(0.35, 0.14, 0.20, 0.10, 0.11, 0.10)

$icdMap = @{
  "NSCLC" = "C34.9"; "CRC" = "C18.9"; "Breast" = "C50.9"; "Melanoma" = "C43.9"; "Prostate" = "C61"
}

$classMap = @{
  "NSCLC" = @("IO_plus_chemo", "TKI", "Chemo_only")
  "CRC" = @("Chemo_plus_targeted", "Chemo_only", "Targeted_only")
  "Breast" = @("Endocrine_plus_CDK", "Chemo_only", "Targeted_only")
  "Melanoma" = @("IO_dual", "BRAF_MEK", "IO_single")
  "Prostate" = @("ADT_plus_ARPI", "Chemo_only", "ADT_only")
}
$routeMap = @{
  "IO_plus_chemo" = "IV"; "TKI" = "Oral"; "Chemo_only" = "IV"; "Chemo_plus_targeted" = "IV"; "Targeted_only" = "Oral"
  "Endocrine_plus_CDK" = "Oral"; "IO_dual" = "IV"; "BRAF_MEK" = "Oral"; "IO_single" = "IV"; "ADT_plus_ARPI" = "Mixed"; "ADT_only" = "Injection"
}

$biomarkerPanel = @{
  "NSCLC" = @("EGFR", "ALK", "KRAS", "PD-L1")
  "CRC" = @("KRAS", "BRAF", "MSI", "HER2")
  "Breast" = @("ER", "PR", "HER2", "PIK3CA")
  "Melanoma" = @("BRAF", "NRAS", "PD-L1")
  "Prostate" = @("AR-V7", "BRCA1", "BRCA2", "MSI")
}
$biomarkerPos = @{
  "EGFR" = 0.18; "ALK" = 0.08; "KRAS" = 0.35; "PD-L1" = 0.30; "BRAF" = 0.14; "MSI" = 0.12
  "HER2" = 0.18; "ER" = 0.72; "PR" = 0.62; "PIK3CA" = 0.20; "NRAS" = 0.15; "AR-V7" = 0.16; "BRCA1" = 0.10; "BRCA2" = 0.13
}
$assayTypes = @("PCR", "NGS", "IHC", "FISH")

$patients = New-Object System.Collections.Generic.List[object]
$obs = New-Object System.Collections.Generic.List[object]
$tumorProfile = New-Object System.Collections.Generic.List[object]
$diagnoses = New-Object System.Collections.Generic.List[object]
$treatments = New-Object System.Collections.Generic.List[object]
$clinicalEvents = New-Object System.Collections.Generic.List[object]
$outcomes = New-Object System.Collections.Generic.List[object]
$biomarkers = New-Object System.Collections.Generic.List[object]

$startIndex = Get-Date "2019-01-01"
$endIndex = Get-Date "2023-12-31"
$maxObs = Get-Date "2026-12-31"

for ($patientNum = 1; $patientNum -le $NPatients; $patientNum++) {
  $sex = Pick-One -Values $sexVals -Weights $sexW
  $birthYear = Get-Random -Minimum 1940 -Maximum 2003
  $age = 2024 - $birthYear
  $race = Pick-One -Values $raceVals -Weights $raceW
  $geo = Pick-One -Values $geoVals -Weights $geoW
  $ins = Pick-One -Values $insVals -Weights $insW
  $indexDate = Random-Date -Start $startIndex -End $endIndex
  $obsStart = $indexDate.AddDays(-(Get-Random -Minimum 30 -Maximum 365))
  $obsMonths = Get-Random -Minimum 12 -Maximum 37
  $obsEnd = $indexDate.AddDays($obsMonths * 30)
  if ($obsEnd -gt $maxObs) { $obsEnd = $maxObs }

  $risk = 0.012 * ($age - 50)
  if ($ins -eq "Medicaid") { $risk += 0.20 }
  if ($ins -eq "Uninsured") { $risk += 0.26 }
  if ($geo -eq "South") { $risk += 0.08 }
  $deathProb = 1.0 / (1.0 + [Math]::Exp(-($risk - 0.85)))
  if ($deathProb -lt 0.20) { $deathProb = 0.20 }
  if ($deathProb -gt 0.40) { $deathProb = 0.40 }
  $died = ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $deathProb)
  $deathDate = $null
  if ($died) {
    $candidate = $indexDate.AddDays((Get-Random -Minimum 60 -Maximum 960))
    if ($candidate -le $obsEnd) { $deathDate = $candidate }
  }
  $lastActivity = $obsEnd.AddDays(-(Get-Random -Minimum 0 -Maximum 90))
  if ($deathDate -and $lastActivity -gt $deathDate) { $lastActivity = $deathDate }

  $patients.Add([pscustomobject]@{
    patient_id = $patientNum; sex = $sex; birth_year = $birthYear; age_at_index = $age
    race_ethnicity = $race; geography = $geo; insurance_proxy = $ins
    index_date = $indexDate.ToString("yyyy-MM-dd")
    death_date = if ($deathDate) { $deathDate.ToString("yyyy-MM-dd") } else { $null }
    last_activity_date = $lastActivity.ToString("yyyy-MM-dd")
  })

  $obs.Add([pscustomobject]@{
    patient_id = $patientNum
    obs_start = $obsStart.ToString("yyyy-MM-dd")
    obs_end = $obsEnd.ToString("yyyy-MM-dd")
    ehr_completeness_flag = if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.85) { 1 } else { 0 }
    claims_completeness_flag = if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.80) { 1 } else { 0 }
    molecular_completeness_flag = if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.65) { 1 } else { 0 }
  })

  $tumor = Pick-One -Values $tumorVals -Weights $tumorW
  $stage = Pick-One -Values $stageVals -Weights $stageW
  $grade = Pick-One -Values $gradeVals -Weights $gradeW
  $hist = Pick-One -Values $histVals -Weights $histW
  $ecog = Pick-One -Values @(0,1,2,3,$null) -Weights @(0.25,0.34,0.22,0.09,0.10)
  $metSites = Pick-One -Values @(0,1,2,3,4) -Weights @(0.24,0.32,0.23,0.14,0.07)

  $tumorProfile.Add([pscustomobject]@{
    patient_id = $patientNum; histology = $hist; stage = $stage; grade = $grade
    metastatic_sites = $metSites; ecog_like = $ecog; tumor_type = $tumor
  })

  $dxDate = $indexDate.AddDays(-(Get-Random -Minimum 0 -Maximum 540))
  $diagnoses.Add([pscustomobject]@{
    patient_id = $patientNum; diagnosis_date = $dxDate.ToString("yyyy-MM-dd")
    icd_code = $icdMap[$tumor]; tumor_type = $tumor; stage_at_dx = $stage; diagnosis_type = "primary_cancer"
  })
  $comorbs = @("I10", "E11.9", "I25.10", "N18.9", "J44.9", "I50.9")
  $k = Get-Random -Minimum 0 -Maximum 4
  if ($k -gt 0) {
    $selected = $comorbs | Get-Random -Count $k
    foreach ($c in $selected) {
      $diagnoses.Add([pscustomobject]@{
        patient_id = $patientNum; diagnosis_date = $indexDate.AddDays(-(Get-Random -Minimum 90 -Maximum 730)).ToString("yyyy-MM-dd")
        icd_code = $c; tumor_type = $null; stage_at_dx = $null; diagnosis_type = "comorbidity"
      })
    }
  }

  $severity = 0.0
  if ($stage -eq "IV") { $severity += 1.0 }
  if ([int]$metSites -ge 2) { $severity += 0.5 }
  if ($ecog -in @(2,3)) { $severity += 0.5 }
  if ($age -gt 72) { $severity += 0.2 }

  $regimens = $classMap[$tumor]
  $armW = if ($severity -gt 1.2) { @(0.30, 0.25, 0.45) } else { @(0.45, 0.35, 0.20) }
  $firstRegimen = Pick-One -Values $regimens -Weights $armW
  $nLines = Pick-One -Values @(1,2,3) -Weights @(0.60,0.30,0.10)
  $start = $indexDate
  for ($lot = 1; $lot -le $nLines; $lot++) {
    $reg = if ($lot -eq 1) { $firstRegimen } else { $regimens | Get-Random }
    $dur = Get-Random -Minimum 90 -Maximum 270
    $end = $start.AddDays($dur)
    $intent = Pick-One -Values @("Palliative", "Curative", "Maintenance") -Weights @(0.62,0.18,0.20)
    $treatments.Add([pscustomobject]@{
      patient_id = $patientNum; start_date = $start.ToString("yyyy-MM-dd"); end_date = $end.ToString("yyyy-MM-dd")
      regimen_name = $reg; line_of_therapy = $lot; route = $routeMap[$reg]; intent = $intent
    })
    $start = $end.AddDays((Get-Random -Minimum 14 -Maximum 90))
  }

  $nEvents = Get-Random -Minimum 8 -Maximum 21
  $labs = @(
    @{n="hemoglobin"; u="g/dL"; m=11.8; s=1.9},
    @{n="albumin"; u="g/dL"; m=3.7; s=0.7},
    @{n="ldh"; u="U/L"; m=220; s=80},
    @{n="creatinine"; u="mg/dL"; m=1.0; s=0.4},
    @{n="wbc"; u="10^9/L"; m=6.8; s=2.1}
  )
  $comorbSignals = @("charlson_cvd", "charlson_diabetes", "charlson_ckd", "charlson_copd")
  for ($e = 0; $e -lt $nEvents; $e++) {
    $eventDate = $indexDate.AddDays(-(Get-Random -Minimum 0 -Maximum 365)).AddDays((Get-Random -Minimum 0 -Maximum 900))
    $isLab = ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.78)
    if ($isLab) {
      $lab = $labs | Get-Random
      $value = [Math]::Round(($lab.m + $lab.s * ([double](Get-Random -Minimum -2.5 -Maximum 2.5))), 2)
      if ($value -lt 0.01) { $value = 0.01 }
      $labName = $lab.n; $units = $lab.u
    } else {
      $value = [double](Get-Random -Minimum 0 -Maximum 3)
      $labName = "utilization_ed_visit"; $units = "count"
    }
    if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.12) { $value = $null }
    $clinicalEvents.Add([pscustomobject]@{
      patient_id = $patientNum; event_date = $eventDate.ToString("yyyy-MM-dd")
      lab_name = $labName; lab_value = $value; units = $units
      performance_status_proxy = Pick-One -Values @(0,1,2,3,$null) -Weights @(0.22,0.34,0.24,0.08,0.12)
      comorbidity_signal = $comorbSignals | Get-Random
    })
  }

  $stageMult = if ($stage -eq "IV") { 1.35 } else { 1.0 }
  $metaMult = if ([int]$metSites -ge 2) { 1.25 } else { 1.0 }
  $ecogMult = if ($ecog -in @(2,3)) { 1.20 } else { 1.0 }
  $progressDays = [int](300 / ($stageMult * $metaMult * $ecogMult) * (Get-Random -Minimum 0.3 -Maximum 1.7))
  if ($progressDays -lt 30) { $progressDays = 30 }
  $progressDate = $indexDate.AddDays($progressDays)
  if ($progressDate -gt $lastActivity -or (Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.15) { $progressDate = $null }

  $hospProb = [Math]::Min(0.65, (0.20 * $stageMult * $ecogMult + 0.10))
  $hospDate = $indexDate.AddDays((Get-Random -Minimum 20 -Maximum 700))
  if ((Get-Random -Minimum 0.0 -Maximum 1.0) -gt $hospProb -or $hospDate -gt $lastActivity) { $hospDate = $null }

  $outcomes.Add([pscustomobject]@{
    patient_id = $patientNum
    progression_proxy_date = if ($progressDate) { $progressDate.ToString("yyyy-MM-dd") } else { $null }
    hospitalization_date = if ($hospDate) { $hospDate.ToString("yyyy-MM-dd") } else { $null }
    adverse_event_grade3plus_flag = if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt [Math]::Min(0.45, 0.15 * $stageMult + 0.08)) { 1 } else { 0 }
    death_date = if ($deathDate) { $deathDate.ToString("yyyy-MM-dd") } else { $null }
  })

  $panel = $biomarkerPanel[$tumor]
  $testCount = Get-Random -Minimum 1 -Maximum ([Math]::Min(4, $panel.Count) + 1)
  $chosen = $panel | Get-Random -Count $testCount
  foreach ($b in $chosen) {
    $specDate = $indexDate.AddDays(-(Get-Random -Minimum 7 -Maximum 240))
    $pos = ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $biomarkerPos[$b])
    $variant = if ($pos) { "$b`_VAR_$(Get-Random -Minimum 1 -Maximum 8)" } else { $null }
    if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt 0.25) { $variant = $null }
    $biomarkers.Add([pscustomobject]@{
      patient_id = $patientNum; specimen_date = $specDate.ToString("yyyy-MM-dd")
      biomarker_name = $b; result = if ($pos) { "Positive" } else { "Negative" }
      variant = $variant; assay_type = $assayTypes | Get-Random
    })
  }
}

$guidelineMap = @(
  [pscustomobject]@{tumor_type="NSCLC";biomarker_pattern="EGFR+";recommended_regimen_class="TKI";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="NSCLC";biomarker_pattern="PD-L1_high";recommended_regimen_class="IO_single";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="NSCLC";biomarker_pattern="Driver_negative";recommended_regimen_class="IO_plus_chemo";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="CRC";biomarker_pattern="RAS_wildtype_left";recommended_regimen_class="Chemo_plus_targeted";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="CRC";biomarker_pattern="RAS_mut";recommended_regimen_class="Chemo_only";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="Breast";biomarker_pattern="HR+_HER2-";recommended_regimen_class="Endocrine_plus_CDK";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="Breast";biomarker_pattern="HER2+";recommended_regimen_class="Targeted_only";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="Melanoma";biomarker_pattern="BRAF+";recommended_regimen_class="BRAF_MEK";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="Melanoma";biomarker_pattern="BRAF-";recommended_regimen_class="IO_dual";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="Prostate";biomarker_pattern="AR_pathway";recommended_regimen_class="ADT_plus_ARPI";line_setting="1L";effective_date="2023-01-01"}
  [pscustomobject]@{tumor_type="Prostate";biomarker_pattern="DNA_repair_defect";recommended_regimen_class="Targeted_only";line_setting="2L+";effective_date="2023-01-01"}
)

$patients | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "patients.csv")
$diagnoses | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "diagnoses.csv")
$treatments | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "treatments.csv")
$clinicalEvents | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "clinical_events.csv")
$outcomes | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "outcomes.csv")
$obs | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "observation_period.csv")
$biomarkers | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "biomarkers.csv")
$tumorProfile | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "tumor_profile.csv")
$guidelineMap | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "guideline_map.csv")

$tables = @{
  "patients" = $patients; "diagnoses" = $diagnoses; "treatments" = $treatments; "clinical_events" = $clinicalEvents
  "outcomes" = $outcomes; "observation_period" = $obs; "biomarkers" = $biomarkers; "tumor_profile" = $tumorProfile
  "guideline_map" = $guidelineMap
}

$metadata = New-Object System.Collections.Generic.List[object]
foreach ($k in $tables.Keys) {
  $rows = $tables[$k]
  $count = $rows.Count
  $first = $rows | Select-Object -First 1
  $colCount = ($first.PSObject.Properties | Measure-Object).Count
  $missing = @{}
  foreach ($prop in $first.PSObject.Properties.Name) {
    $nullCount = ($rows | Where-Object { $null -eq $_.$prop -or $_.$prop -eq "" } | Measure-Object).Count
    $missing[$prop] = [math]::Round(($nullCount / [math]::Max(1, $count)), 4)
  }
  $metadata.Add([pscustomobject]@{
    table_name = $k
    row_count = $count
    column_count = $colCount
    refresh_date = (Get-Date).ToString("yyyy-MM-dd")
    missingness_json = ($missing | ConvertTo-Json -Compress)
  })
}

$metadata | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir "table_metadata.csv")

$provenance = @{
  generator_version = "1.0.0-ps"
  seed = $Seed
  n_patients = $NPatients
  created_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  tables = @{
    patients = "Baseline demographics, censoring, and survival anchor table."
    diagnoses = "Primary cancer diagnosis and comorbidity-coded diagnosis history."
    treatments = "Longitudinal treatment exposure records with line of therapy."
    clinical_events = "Labs, utilization proxies, performance status, and comorbidity signals."
    outcomes = "Time-to-event outcomes including progression proxy and death."
    observation_period = "Observation boundaries and source completeness flags."
    biomarkers = "Molecular and biomarker test outcomes and assay metadata."
    tumor_profile = "Tumor characterization and severity/confounding proxies."
    guideline_map = "Synthetic oncology guideline mapping reference."
    table_metadata = "Generated table-level refresh and missingness statistics."
  }
  known_limitations = @(
    "Synthetic data does not reflect real patient identities or true clinical pathways.",
    "Guideline mapping is a simplified proxy and not a substitute for NCCN source documents.",
    "Progression proxy is algorithmic and should not be treated as clinically adjudicated PFS.",
    "Missingness mechanism is simulated and may not fully reproduce MNAR patterns."
  )
}
$provenance | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $OutputDir "data_provenance.json")

$deathRate = [math]::Round((($patients | Where-Object { $_.death_date }) | Measure-Object).Count / $patients.Count, 3)
$followupMonths = [math]::Round((($obs | ForEach-Object {
  ([datetime]$_.obs_end - [datetime]$_.obs_start).Days / 30.4
} | Measure-Object -Average).Average), 1)

Write-Output "Generated data in: $OutputDir"
Write-Output "Patients: $($patients.Count)"
Write-Output "Death event rate: $deathRate"
Write-Output "Mean observation window (months): $followupMonths"
Write-Output "Tables written: patients, diagnoses, treatments, clinical_events, outcomes, observation_period, biomarkers, tumor_profile, guideline_map, table_metadata, data_provenance.json"
