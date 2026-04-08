import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


@dataclass
class Config:
    n_patients: int = 8000
    seed: int = 42
    output_dir: str = "synthetic_rwe_data"


def random_date_series(rng: np.random.Generator, start: str, end: str, size: int) -> pd.Series:
    start_ts = pd.Timestamp(start).value // 10**9
    end_ts = pd.Timestamp(end).value // 10**9
    random_seconds = rng.integers(start_ts, end_ts, size=size)
    return pd.to_datetime(random_seconds, unit="s")


def build_patients(rng: np.random.Generator, n: int):
    patient_id = np.arange(1, n + 1)
    sex = rng.choice(["F", "M"], size=n, p=[0.52, 0.48])
    birth_year = rng.integers(1940, 2003, size=n)
    age_at_index = 2024 - birth_year
    race_ethnicity = rng.choice(
        ["White", "Black", "Hispanic", "Asian", "Other", "Unknown"],
        size=n,
        p=[0.52, 0.16, 0.14, 0.08, 0.06, 0.04],
    )
    geography = rng.choice(
        ["Northeast", "Midwest", "South", "West"], size=n, p=[0.2, 0.24, 0.36, 0.2]
    )
    insurance_proxy = rng.choice(
        ["Commercial", "Medicare", "Medicaid", "Uninsured", "Other"],
        size=n,
        p=[0.36, 0.42, 0.14, 0.04, 0.04],
    )
    index_date = random_date_series(rng, "2019-01-01", "2023-12-31", n).normalize()

    obs_months = rng.integers(12, 37, size=n)
    obs_start = index_date - pd.to_timedelta(rng.integers(30, 365, size=n), unit="D")
    obs_end = index_date + pd.to_timedelta(obs_months * 30, unit="D")
    obs_end = pd.Series(np.minimum(obs_end.values.astype("datetime64[ns]"), np.datetime64("2026-12-31")))

    risk_score = (
        0.012 * (age_at_index - 50)
        + (insurance_proxy == "Medicaid") * 0.20
        + (insurance_proxy == "Uninsured") * 0.26
        + (geography == "South") * 0.08
    )
    death_prob = 1 / (1 + np.exp(-(risk_score - 0.85)))
    death_prob = np.clip(death_prob, 0.20, 0.40)
    has_death = rng.binomial(1, death_prob, size=n).astype(bool)
    death_days = rng.integers(60, 960, size=n)
    death_date = index_date + pd.to_timedelta(death_days, unit="D")
    death_date = pd.Series(np.where(has_death, death_date, pd.NaT), dtype="datetime64[ns]")
    death_date = pd.Series(np.where((death_date.notna()) & (death_date > obs_end), pd.NaT, death_date))

    last_activity_offset = rng.integers(0, 90, size=n)
    last_activity_date = obs_end - pd.to_timedelta(last_activity_offset, unit="D")
    last_activity_date = pd.Series(
        np.where(
            pd.notna(death_date),
            np.minimum(last_activity_date.values.astype("datetime64[ns]"), death_date.values.astype("datetime64[ns]")),
            last_activity_date.values.astype("datetime64[ns]"),
        ),
        dtype="datetime64[ns]",
    )

    patients = pd.DataFrame(
        {
            "patient_id": patient_id,
            "sex": sex,
            "birth_year": birth_year,
            "age_at_index": age_at_index,
            "race_ethnicity": race_ethnicity,
            "geography": geography,
            "insurance_proxy": insurance_proxy,
            "index_date": index_date,
            "death_date": death_date,
            "last_activity_date": last_activity_date,
        }
    )

    observation_period = pd.DataFrame(
        {
            "patient_id": patient_id,
            "obs_start": obs_start,
            "obs_end": obs_end,
            "ehr_completeness_flag": rng.choice([0, 1], size=n, p=[0.15, 0.85]),
            "claims_completeness_flag": rng.choice([0, 1], size=n, p=[0.20, 0.80]),
            "molecular_completeness_flag": rng.choice([0, 1], size=n, p=[0.35, 0.65]),
        }
    )
    return patients, observation_period


def build_tumor_and_diagnoses(rng: np.random.Generator, patients: pd.DataFrame):
    n = len(patients)
    tumor_type = rng.choice(
        ["NSCLC", "CRC", "Breast", "Melanoma", "Prostate"],
        size=n,
        p=[0.28, 0.22, 0.22, 0.12, 0.16],
    )
    stage = rng.choice(["I", "II", "III", "IV"], size=n, p=[0.12, 0.20, 0.30, 0.38])
    grade = rng.choice(["Low", "Intermediate", "High", "Unknown"], size=n, p=[0.22, 0.37, 0.31, 0.10])
    histology = rng.choice(
        ["Adenocarcinoma", "Squamous", "Ductal", "Serous", "Mixed", "Other"],
        size=n,
        p=[0.35, 0.14, 0.20, 0.10, 0.11, 0.10],
    )
    ecog = rng.choice([0, 1, 2, 3, np.nan], size=n, p=[0.25, 0.34, 0.22, 0.09, 0.10])
    metastatic_sites = rng.choice([0, 1, 2, 3, 4], size=n, p=[0.24, 0.32, 0.23, 0.14, 0.07])

    tumor_profile = pd.DataFrame(
        {
            "patient_id": patients["patient_id"],
            "histology": histology,
            "stage": stage,
            "grade": grade,
            "metastatic_sites": metastatic_sites,
            "ecog_like": ecog,
            "tumor_type": tumor_type,
        }
    )

    icd_map = {
        "NSCLC": "C34.9",
        "CRC": "C18.9",
        "Breast": "C50.9",
        "Melanoma": "C43.9",
        "Prostate": "C61",
    }
    diagnosis_date = patients["index_date"] - pd.to_timedelta(rng.integers(0, 540, size=n), unit="D")

    primary_dx = pd.DataFrame(
        {
            "patient_id": patients["patient_id"],
            "diagnosis_date": diagnosis_date,
            "icd_code": [icd_map[t] for t in tumor_type],
            "tumor_type": tumor_type,
            "stage_at_dx": stage,
            "diagnosis_type": "primary_cancer",
        }
    )

    comorb_codes = ["I10", "E11.9", "I25.10", "N18.9", "J44.9", "I50.9"]
    comorb_rows = []
    for pid, idx_date in zip(patients["patient_id"].values, patients["index_date"].values):
        k = rng.integers(0, 4)
        if k == 0:
            continue
        picked = rng.choice(comorb_codes, size=k, replace=False)
        for code in picked:
            comorb_rows.append(
                {
                    "patient_id": int(pid),
                    "diagnosis_date": pd.Timestamp(idx_date) - pd.Timedelta(days=int(rng.integers(90, 730))),
                    "icd_code": code,
                    "tumor_type": None,
                    "stage_at_dx": None,
                    "diagnosis_type": "comorbidity",
                }
            )
    diagnoses = pd.concat([primary_dx, pd.DataFrame(comorb_rows)], ignore_index=True)
    return tumor_profile, diagnoses


def build_treatments(rng: np.random.Generator, patients: pd.DataFrame, tumor_profile: pd.DataFrame):
    treatment_rows = []
    class_map = {
        "NSCLC": ["IO_plus_chemo", "TKI", "Chemo_only"],
        "CRC": ["Chemo_plus_targeted", "Chemo_only", "Targeted_only"],
        "Breast": ["Endocrine_plus_CDK", "Chemo_only", "Targeted_only"],
        "Melanoma": ["IO_dual", "BRAF_MEK", "IO_single"],
        "Prostate": ["ADT_plus_ARPI", "Chemo_only", "ADT_only"],
    }
    route_map = {
        "IO_plus_chemo": "IV",
        "TKI": "Oral",
        "Chemo_only": "IV",
        "Chemo_plus_targeted": "IV",
        "Targeted_only": "Oral",
        "Endocrine_plus_CDK": "Oral",
        "IO_dual": "IV",
        "BRAF_MEK": "Oral",
        "IO_single": "IV",
        "ADT_plus_ARPI": "Mixed",
        "ADT_only": "Injection",
    }

    merged = patients[["patient_id", "index_date", "age_at_index", "insurance_proxy", "geography"]].merge(
        tumor_profile[["patient_id", "tumor_type", "stage", "metastatic_sites", "ecog_like"]],
        on="patient_id",
        how="left",
    )
    for _, row in merged.iterrows():
        n_lines = int(rng.choice([1, 2, 3], p=[0.60, 0.30, 0.10]))
        start = pd.Timestamp(row["index_date"])
        choices = class_map[row["tumor_type"]]
        severity = (
            (row["stage"] == "IV") * 1.0
            + (row["metastatic_sites"] >= 2) * 0.5
            + (row["ecog_like"] in [2, 3]) * 0.5
            + (row["age_at_index"] > 72) * 0.2
        )
        arm_probs = np.array([0.45, 0.35, 0.20], dtype=float)
        if severity > 1.2:
            arm_probs = np.array([0.30, 0.25, 0.45], dtype=float)
        regimen_first = rng.choice(choices, p=arm_probs / arm_probs.sum())

        for lot in range(1, n_lines + 1):
            regimen = regimen_first if lot == 1 else rng.choice(choices)
            duration = int(rng.integers(90, 270))
            end = start + pd.Timedelta(days=duration)
            intent = rng.choice(["Palliative", "Curative", "Maintenance"], p=[0.62, 0.18, 0.20])
            treatment_rows.append(
                {
                    "patient_id": int(row["patient_id"]),
                    "start_date": start,
                    "end_date": end,
                    "regimen_name": regimen,
                    "line_of_therapy": lot,
                    "route": route_map.get(regimen, "IV"),
                    "intent": intent,
                }
            )
            start = end + pd.Timedelta(days=int(rng.integers(14, 90)))
    return pd.DataFrame(treatment_rows)


def build_clinical_events(rng: np.random.Generator, patients: pd.DataFrame):
    labs = [
        ("hemoglobin", "g/dL", 11.8, 1.9),
        ("albumin", "g/dL", 3.7, 0.7),
        ("ldh", "U/L", 220, 80),
        ("creatinine", "mg/dL", 1.0, 0.4),
        ("wbc", "10^9/L", 6.8, 2.1),
    ]
    comorb_signals = ["charlson_cvd", "charlson_diabetes", "charlson_ckd", "charlson_copd"]
    rows = []
    for _, p in patients.iterrows():
        pid = int(p["patient_id"])
        idx = pd.Timestamp(p["index_date"])
        n_events = int(rng.integers(8, 21))
        for _ in range(n_events):
            event_date = idx - pd.Timedelta(days=int(rng.integers(0, 365))) + pd.Timedelta(
                days=int(rng.integers(0, 900))
            )
            if rng.random() < 0.78:
                lab_name, units, mu, sd = labs[int(rng.integers(0, len(labs)))]
                value = float(np.round(rng.normal(mu, sd), 2))
                value = max(value, 0.01)
                perf = rng.choice([0, 1, 2, 3, np.nan], p=[0.22, 0.34, 0.24, 0.08, 0.12])
                comorb = rng.choice(comorb_signals)
            else:
                lab_name = "utilization_ed_visit"
                units = "count"
                value = float(rng.integers(0, 3))
                perf = rng.choice([0, 1, 2, 3, np.nan], p=[0.20, 0.36, 0.23, 0.10, 0.11])
                comorb = rng.choice(comorb_signals)
            rows.append(
                {
                    "patient_id": pid,
                    "event_date": event_date,
                    "lab_name": lab_name,
                    "lab_value": value,
                    "units": units,
                    "performance_status_proxy": perf,
                    "comorbidity_signal": comorb,
                }
            )
    clinical_events = pd.DataFrame(rows)
    missing_mask = rng.random(len(clinical_events)) < 0.12
    clinical_events.loc[missing_mask, "lab_value"] = np.nan
    return clinical_events


def build_biomarkers(rng: np.random.Generator, patients: pd.DataFrame, tumor_profile: pd.DataFrame):
    panels = {
        "NSCLC": ["EGFR", "ALK", "KRAS", "PD-L1"],
        "CRC": ["KRAS", "BRAF", "MSI", "HER2"],
        "Breast": ["ER", "PR", "HER2", "PIK3CA"],
        "Melanoma": ["BRAF", "NRAS", "PD-L1"],
        "Prostate": ["AR-V7", "BRCA1", "BRCA2", "MSI"],
    }
    positivity = {
        "EGFR": 0.18,
        "ALK": 0.08,
        "KRAS": 0.35,
        "PD-L1": 0.30,
        "BRAF": 0.14,
        "MSI": 0.12,
        "HER2": 0.18,
        "ER": 0.72,
        "PR": 0.62,
        "PIK3CA": 0.20,
        "NRAS": 0.15,
        "AR-V7": 0.16,
        "BRCA1": 0.10,
        "BRCA2": 0.13,
    }
    assay_types = ["PCR", "NGS", "IHC", "FISH"]
    records = []
    merged = patients[["patient_id", "index_date"]].merge(
        tumor_profile[["patient_id", "tumor_type"]], on="patient_id", how="left"
    )
    for _, row in merged.iterrows():
        tumor = row["tumor_type"]
        panel = panels[tumor]
        n_tests = int(rng.integers(1, min(4, len(panel)) + 1))
        chosen = rng.choice(panel, size=n_tests, replace=False)
        for biomarker in chosen:
            specimen_date = pd.Timestamp(row["index_date"]) - pd.Timedelta(days=int(rng.integers(7, 240)))
            pos = rng.random() < positivity.get(biomarker, 0.20)
            result = "Positive" if pos else "Negative"
            variant = f"{biomarker}_VAR_{int(rng.integers(1, 8))}" if pos else None
            records.append(
                {
                    "patient_id": int(row["patient_id"]),
                    "specimen_date": specimen_date,
                    "biomarker_name": biomarker,
                    "result": result,
                    "variant": variant,
                    "assay_type": rng.choice(assay_types),
                }
            )
    biomarkers = pd.DataFrame(records)
    miss_variant = rng.random(len(biomarkers)) < 0.25
    biomarkers.loc[miss_variant, "variant"] = np.nan
    return biomarkers


def build_outcomes(rng: np.random.Generator, patients: pd.DataFrame, tumor_profile: pd.DataFrame):
    merged = patients.merge(tumor_profile[["patient_id", "stage", "metastatic_sites", "ecog_like"]], on="patient_id")
    records = []
    for _, row in merged.iterrows():
        idx = pd.Timestamp(row["index_date"])
        obs_end = pd.Timestamp(row["last_activity_date"])
        stage_mult = 1.35 if row["stage"] == "IV" else 1.0
        meta_mult = 1.25 if row["metastatic_sites"] >= 2 else 1.0
        ecog_mult = 1.20 if row["ecog_like"] in [2, 3] else 1.0
        base_progress_days = int(rng.exponential(300 / (stage_mult * meta_mult * ecog_mult)))
        progression_proxy_date = idx + pd.Timedelta(days=max(30, base_progress_days))
        if progression_proxy_date > obs_end or rng.random() < 0.15:
            progression_proxy_date = pd.NaT

        hosp_prob = min(0.65, 0.20 * stage_mult * ecog_mult + 0.10)
        hospitalization_date = idx + pd.Timedelta(days=int(rng.integers(20, 700)))
        if rng.random() > hosp_prob or hospitalization_date > obs_end:
            hospitalization_date = pd.NaT

        ae_grade3plus = int(rng.random() < min(0.45, 0.15 * stage_mult + 0.08))
        death_date = row["death_date"]
        records.append(
            {
                "patient_id": int(row["patient_id"]),
                "progression_proxy_date": progression_proxy_date,
                "hospitalization_date": hospitalization_date,
                "adverse_event_grade3plus_flag": ae_grade3plus,
                "death_date": death_date,
            }
        )
    return pd.DataFrame(records)


def build_guideline_map():
    return pd.DataFrame(
        [
            ("NSCLC", "EGFR+", "TKI", "1L", "2023-01-01"),
            ("NSCLC", "PD-L1_high", "IO_single", "1L", "2023-01-01"),
            ("NSCLC", "Driver_negative", "IO_plus_chemo", "1L", "2023-01-01"),
            ("CRC", "RAS_wildtype_left", "Chemo_plus_targeted", "1L", "2023-01-01"),
            ("CRC", "RAS_mut", "Chemo_only", "1L", "2023-01-01"),
            ("Breast", "HR+_HER2-", "Endocrine_plus_CDK", "1L", "2023-01-01"),
            ("Breast", "HER2+", "Targeted_only", "1L", "2023-01-01"),
            ("Melanoma", "BRAF+", "BRAF_MEK", "1L", "2023-01-01"),
            ("Melanoma", "BRAF-", "IO_dual", "1L", "2023-01-01"),
            ("Prostate", "AR_pathway", "ADT_plus_ARPI", "1L", "2023-01-01"),
            ("Prostate", "DNA_repair_defect", "Targeted_only", "2L+", "2023-01-01"),
        ],
        columns=[
            "tumor_type",
            "biomarker_pattern",
            "recommended_regimen_class",
            "line_setting",
            "effective_date",
        ],
    )


def summarize_table_metadata(tables: dict):
    metadata_rows = []
    for name, df in tables.items():
        n_rows = len(df)
        n_cols = len(df.columns)
        missing_rates = df.isna().mean().to_dict()
        metadata_rows.append(
            {
                "table_name": name,
                "row_count": int(n_rows),
                "column_count": int(n_cols),
                "refresh_date": pd.Timestamp.today().normalize().strftime("%Y-%m-%d"),
                "missingness_json": json.dumps({k: round(float(v), 4) for k, v in missing_rates.items()}),
            }
        )
    return pd.DataFrame(metadata_rows)


def build_data_provenance(cfg: Config, tables: dict):
    table_defs = {
        "patients": "Baseline demographics, censoring, and survival anchor table.",
        "diagnoses": "Primary cancer diagnosis and comorbidity-coded diagnosis history.",
        "treatments": "Longitudinal treatment exposure records with line of therapy.",
        "clinical_events": "Labs, utilization proxies, performance status, and comorbidity signals.",
        "outcomes": "Time-to-event outcomes including progression proxy and death.",
        "observation_period": "Observation boundaries and source completeness flags.",
        "biomarkers": "Molecular and biomarker test outcomes and assay metadata.",
        "tumor_profile": "Tumor characterization and severity/confounding proxies.",
        "guideline_map": "Synthetic oncology guideline mapping reference.",
        "table_metadata": "Generated table-level refresh and missingness statistics.",
    }
    known_limitations = [
        "Synthetic data does not reflect real patient identities or true clinical pathways.",
        "Guideline mapping is a simplified proxy and not a substitute for NCCN source documents.",
        "Progression proxy is algorithmic and should not be treated as clinically adjudicated PFS.",
        "Missingness mechanism is simulated and may not fully reproduce MNAR patterns.",
    ]
    return {
        "generator_version": "1.0.0",
        "seed": cfg.seed,
        "n_patients": cfg.n_patients,
        "created_at_utc": pd.Timestamp.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tables": table_defs,
        "known_limitations": known_limitations,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic RWE oncology-like datasets.")
    parser.add_argument("--n-patients", type=int, default=8000, help="Number of synthetic patients (5000-20000).")
    parser.add_argument("--seed", type=int, default=42, help="Random seed.")
    parser.add_argument("--output-dir", type=str, default="synthetic_rwe_data", help="Output folder for CSV files.")
    args = parser.parse_args()

    cfg = Config(n_patients=args.n_patients, seed=args.seed, output_dir=args.output_dir)
    if cfg.n_patients < 5000 or cfg.n_patients > 20000:
        raise ValueError("n_patients must be between 5000 and 20000 for requested design targets.")

    out_dir = Path(cfg.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rng = np.random.default_rng(cfg.seed)

    patients, observation_period = build_patients(rng, cfg.n_patients)
    tumor_profile, diagnoses = build_tumor_and_diagnoses(rng, patients)
    treatments = build_treatments(rng, patients, tumor_profile)
    clinical_events = build_clinical_events(rng, patients)
    biomarkers = build_biomarkers(rng, patients, tumor_profile)
    outcomes = build_outcomes(rng, patients, tumor_profile)
    guideline_map = build_guideline_map()

    tables = {
        "patients": patients,
        "diagnoses": diagnoses,
        "treatments": treatments,
        "clinical_events": clinical_events,
        "outcomes": outcomes,
        "observation_period": observation_period,
        "biomarkers": biomarkers,
        "tumor_profile": tumor_profile,
        "guideline_map": guideline_map,
    }

    for name, df in tables.items():
        df.to_csv(out_dir / f"{name}.csv", index=False)

    table_metadata = summarize_table_metadata(tables)
    table_metadata.to_csv(out_dir / "table_metadata.csv", index=False)
    tables["table_metadata"] = table_metadata

    provenance = build_data_provenance(cfg, tables)
    with open(out_dir / "data_provenance.json", "w", encoding="utf-8") as f:
        json.dump(provenance, f, indent=2)

    event_rate = pd.notna(patients["death_date"]).mean()
    followup_months = (
        (pd.to_datetime(observation_period["obs_end"]) - pd.to_datetime(patients["index_date"])).dt.days / 30.4
    ).median()
    print(f"Generated data in: {out_dir.resolve()}")
    print(f"Patients: {len(patients)}")
    print(f"Death event rate: {event_rate:.3f}")
    print(f"Median follow-up (months): {followup_months:.1f}")
    print("Tables written: " + ", ".join(sorted(tables.keys())))


if __name__ == "__main__":
    main()
