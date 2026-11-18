-- Phase 1 exploration of the 2025 Q1 N-CEN data set.
-- Runs against data/explore_2025q1.db, a throwaway database built in
-- notebooks/01_explore.ipynb (all columns loaded as text, only empty
-- fields treated as missing).


-- ===================================================================
-- 1. Keys: what does one row in each table represent?
-- ===================================================================

-- Is ACCESSION_NUMBER unique in SUBMISSION and REGISTRANT?
-- Result: yes, 1,956 rows and 1,956 distinct in both.
SELECT COUNT(*), COUNT(DISTINCT ACCESSION_NUMBER) FROM SUBMISSION;
SELECT COUNT(*), COUNT(DISTINCT ACCESSION_NUMBER) FROM REGISTRANT;

-- Do the two tables hold the same filings? Both should return 0 rows.
-- Result: 0 rows both ways.
SELECT ACCESSION_NUMBER FROM SUBMISSION
EXCEPT
SELECT ACCESSION_NUMBER FROM REGISTRANT;

SELECT ACCESSION_NUMBER FROM REGISTRANT
EXCEPT
SELECT ACCESSION_NUMBER FROM SUBMISSION;

-- Is FUND_ID unique in FUND_REPORTED_INFO, and how many filings have funds?
-- Result: 6,881 rows, 6,881 distinct FUND_IDs, from 1,237 filings.
SELECT COUNT(*), COUNT(DISTINCT FUND_ID), COUNT(DISTINCT ACCESSION_NUMBER)
FROM FUND_REPORTED_INFO;


-- ===================================================================
-- 2. Links: does every row join to its parent?
-- ===================================================================

-- Funds with no matching filing. Result: 0.
SELECT FRI.ACCESSION_NUMBER, FRI.FUND_ID, FRI.FUND_NAME
FROM FUND_REPORTED_INFO FRI
LEFT JOIN SUBMISSION S ON FRI.ACCESSION_NUMBER = S.ACCESSION_NUMBER
WHERE S.ACCESSION_NUMBER IS NULL;

-- Custodian rows with no matching fund. Result: 0.
SELECT C.FUND_ID, C.CUSTODIAN_NAME
FROM CUSTODIAN C
LEFT JOIN FUND_REPORTED_INFO FRI ON C.FUND_ID = FRI.FUND_ID
WHERE FRI.FUND_ID IS NULL;


-- ===================================================================
-- 3. Filing types
-- ===================================================================

-- Result: 1,876 N-CEN and 80 N-CEN/A.
SELECT SUBMISSION_TYPE, COUNT(*)
FROM SUBMISSION
GROUP BY SUBMISSION_TYPE;

-- Which filings have fund rows, by registration form?
-- Result: N-1A 873 with funds and 23 without; N-2 361 with; N-3 3 with;
-- N-4 417, N-6 240 and S-6 39 all without (insurance separate accounts
-- and unit investment trusts).
SELECT r.INVESTMENT_COMPANY_TYPE,
       CASE WHEN f.ACCESSION_NUMBER IS NULL THEN 'no funds' ELSE 'has funds' END AS has_funds,
       COUNT(*) AS n_filings
FROM REGISTRANT r
LEFT JOIN (SELECT DISTINCT ACCESSION_NUMBER FROM FUND_REPORTED_INFO) f
       ON r.ACCESSION_NUMBER = f.ACCESSION_NUMBER
GROUP BY r.INVESTMENT_COMPANY_TYPE, has_funds;

-- The 23 N-1A filings with no fund rows.
-- Result: all original N-CENs. 13 are last filings with 0 series, 2 have
-- 0 series, and 8 report series but have no fund rows (for example
-- ETF Series Solutions, 53 series). Recheck the 8 across quarters.
SELECT r.REGISTRANT_NAME, r.TOTAL_SERIES, r.IS_LAST_FILING, s.SUBMISSION_TYPE
FROM REGISTRANT r
LEFT JOIN (SELECT DISTINCT ACCESSION_NUMBER FROM FUND_REPORTED_INFO) f
       ON r.ACCESSION_NUMBER = f.ACCESSION_NUMBER
LEFT JOIN SUBMISSION s ON r.ACCESSION_NUMBER = s.ACCESSION_NUMBER
WHERE f.ACCESSION_NUMBER IS NULL
  AND r.INVESTMENT_COMPANY_TYPE = 'N-1A'
ORDER BY r.REGISTRANT_NAME;


-- ===================================================================
-- 4. Missing values and placeholders in CUSTODIAN
-- ===================================================================

-- NULLs per column (86,839 rows).
-- Result: STATE 77,894 and OTHER_CUSTODIAN_DESC 86,757, all others 0.
-- Before the loading fix, pandas also turned 'NA' and 'N/A' into NULL.
SELECT
    COUNT(*)                               AS total_rows,
    COUNT(*) - COUNT(FUND_ID)              AS fund_id_null,
    COUNT(*) - COUNT(SOURCE)               AS source_null,
    COUNT(*) - COUNT(CUSTODIAN_NAME)       AS name_null,
    COUNT(*) - COUNT(CUSTODIAN_LEI)        AS lei_null,
    COUNT(*) - COUNT(STATE)                AS state_null,
    COUNT(*) - COUNT(COUNTRY)              AS country_null,
    COUNT(*) - COUNT(IS_AFFILIATED)        AS affiliated_null,
    COUNT(*) - COUNT(IS_SUB_CUSTODIAN)     AS sub_custodian_null,
    COUNT(*) - COUNT(CUSTODY_TYPE)         AS custody_type_null,
    COUNT(*) - COUNT(OTHER_CUSTODIAN_DESC) AS other_desc_null
FROM CUSTODIAN;

-- 'NA' in COUNTRY is Namibia, not missing. Result: 225 rows.
SELECT COUNT(*) FROM CUSTODIAN WHERE COUNTRY = 'NA';

-- A real LEI is 20 characters. Result: the only other value is 'N/A' (8,645 rows).
SELECT CUSTODIAN_LEI, COUNT(*)
FROM CUSTODIAN
WHERE LENGTH(CUSTODIAN_LEI) <> 20
GROUP BY CUSTODIAN_LEI
ORDER BY COUNT(*) DESC;

-- Placeholder custodian names.
-- Result: one main custodian row with name 'N/A', LEI 'N/A', country 'XX'.
SELECT *
FROM CUSTODIAN
WHERE CUSTODIAN_NAME IN ('NA', 'N/A', 'n/a', 'NULL', 'null', 'None', 'nan');

-- First look at the rows. Result: mostly foreign sub-custodians
-- (rule 17f-5), one per country, which is why there are about 12.6
-- custodian rows per fund.
SELECT * FROM CUSTODIAN LIMIT 15;


-- ===================================================================
-- 5. Tracing one fund: BNY Mellon Global Stock Fund (S000015656)
-- ===================================================================

-- BNY-named funds. Result: 47, including Nationwide/NVIT funds that BNY
-- sub-advises but doesn't run.
SELECT FUND_NAME, FUND_ID, ACCESSION_NUMBER
FROM FUND_REPORTED_INFO
WHERE FUND_NAME LIKE '%BNY%';

-- The fund and its filings.
-- Result: same series and period end (30 Nov 2024) in two filings, an
-- N-CEN on 13 Feb 2025 and an N-CEN/A on 14 Feb 2025.
SELECT f.FUND_ID, f.SERIES_ID, f.ACCESSION_NUMBER,
       s.SUBMISSION_TYPE, s.FILING_DATE, s.REPORT_ENDING_PERIOD
FROM FUND_REPORTED_INFO f
JOIN SUBMISSION s ON f.ACCESSION_NUMBER = s.ACCESSION_NUMBER
WHERE f.FUND_NAME = 'BNY Mellon Global Stock Fund';

-- The fund family. Result: BNY Mellon Strategic Funds, Inc., CIK 0000737520, 3 series.
SELECT REGISTRANT_NAME, CIK, TOTAL_SERIES
FROM REGISTRANT
WHERE ACCESSION_NUMBER IN ('0001752724-25-022790', '0001752724-25-024251');

-- Custodian rows per filing. Result: 18 rows each, 17 of them sub-custodians,
-- so the amendment repeats the original in full.
SELECT FUND_ID,
       COUNT(*) AS n_custodians,
       SUM(CASE WHEN IS_SUB_CUSTODIAN = 'Y' THEN 1 ELSE 0 END) AS n_sub_custodians
FROM CUSTODIAN
WHERE FUND_ID IN ('0001752724-25-022790_0000737520_S000015656',
                  '0001752724-25-024251_0000737520_S000015656')
GROUP BY FUND_ID;

-- The main custodian.
-- Result: The Bank of New York Mellon, affiliated (Y), custody type
-- "Self - rule 17f-2" rather than "Bank - section 17(f)(1)".
SELECT CUSTODIAN_NAME, CUSTODIAN_LEI, COUNTRY, IS_AFFILIATED, CUSTODY_TYPE
FROM CUSTODIAN
WHERE FUND_ID IN ('0001752724-25-022790_0000737520_S000015656',
                  '0001752724-25-024251_0000737520_S000015656')
  AND IS_SUB_CUSTODIAN = 'N';

-- Affiliated custodians.
-- Result: BNY itself plus BNY Ireland and UK (same LEI as the US bank),
-- BNY SA/NV and CIBC Mellon (their own LEIs) as sub-custodians.
SELECT CUSTODIAN_NAME, CUSTODIAN_LEI, COUNTRY, IS_AFFILIATED, CUSTODY_TYPE, IS_SUB_CUSTODIAN
FROM CUSTODIAN
WHERE FUND_ID IN ('0001752724-25-022790_0000737520_S000015656',
                  '0001752724-25-024251_0000737520_S000015656')
  AND IS_AFFILIATED = 'Y';
  
-- Custody type by sub-custodian flag.
-- Result: 8 of the 9 types in the readme appear (no insurance company
-- sponsor, rule 26a-2). 8,102 rows are marked as not sub-custodians, for
-- 6,881 funds, so IS_SUB_CUSTODIAN = 'N' alone does not identify the main
-- custodian. Of those rows, Bank (6,800) and Self (326) look like real main
-- custodians. Futures commission merchants (669) and securities
-- depositories (109 US, 93 foreign) are not competing for custody mandates.
-- Unclear: foreign custodian (85), Other (17), exchange (3).
-- 566 bank rows are marked as sub-custodians and should stay out.
SELECT CUSTODY_TYPE, IS_SUB_CUSTODIAN, COUNT(*) FROM CUSTODIAN
GROUP BY CUSTODY_TYPE, IS_SUB_CUSTODIAN
ORDER BY COUNT(*) DESC;


-- Candidate rule for main custodian: IS_SUB_CUSTODIAN = 'N' and custody
-- type Bank or Self. How many candidates does each fund have?
-- Result: 0 = 96 funds, 1 = 6,499 (94%), 2 = 265, 3 = 13, 5 to 8 = 8.
-- Check: funds add up to 6,881 and candidate rows to 7,126.
-- Phase 4 needs a rule for funds with no candidate and for funds with
-- more than one.
WITH main_cust AS (SELECT * FROM CUSTODIAN 
WHERE IS_SUB_CUSTODIAN = 'N' AND (CUSTODY_TYPE LIKE 'Bank%' OR CUSTODY_TYPE LIKE 'Self%')),
per_fund AS (SELECT f.FUND_ID, COUNT(m.FUND_ID) AS n_main FROM FUND_REPORTED_INFO f
LEFT JOIN main_cust m ON f.FUND_ID = m.FUND_ID
GROUP BY f.FUND_ID)
SELECT n_main, COUNT(*) AS n_funds
FROM per_fund
GROUP BY n_main
ORDER BY n_main;


-- What do the 96 funds with no candidate main custodian list instead?
-- Result: 62 funds list only a US securities depository (one row each),
-- 15 list no custodians at all, 12 list a bank flagged as sub-custodian
-- (possibly a filing error), a few list a foreign custodian (3) or an
-- exchange (2) as non-sub.
WITH main_cust AS (SELECT * FROM CUSTODIAN 
WHERE IS_SUB_CUSTODIAN = 'N' AND (CUSTODY_TYPE LIKE 'Bank%' OR CUSTODY_TYPE LIKE 'Self%')),
per_fund AS (SELECT f.FUND_ID, COUNT(m.FUND_ID) AS n_main FROM FUND_REPORTED_INFO f
LEFT JOIN main_cust m ON f.FUND_ID = m.FUND_ID
GROUP BY f.FUND_ID)
SELECT c.CUSTODY_TYPE, c.IS_SUB_CUSTODIAN,
       COUNT(*) AS n_rows,
       COUNT(DISTINCT p.FUND_ID) AS n_funds
FROM per_fund p
LEFT JOIN CUSTODIAN c ON p.FUND_ID = c.FUND_ID
WHERE p.n_main = 0
GROUP BY c.CUSTODY_TYPE, c.IS_SUB_CUSTODIAN
ORDER BY n_funds DESC;



