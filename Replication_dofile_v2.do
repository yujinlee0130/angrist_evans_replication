clear all
prog drop _all
capture log close
set more off

cd "/Users/yujinlee/Google Drive/NYU/Fall 2022/AEM/Replication_Exercise"
use "raw pums80 slim.dta", clear
log using "Replication_log_file_v2.smcl", replace

*Part 1: Create mother only data-----------------------------------------------*
* Drop unnecessary variables
drop stateus us80a_statefip

* Create unique person IDs to be used for mothers
tostring us80a_serial us80a_momloc, replace
decode us80a_sploc, gen(us80a_sploc_new)
egen personid = concat (us80a_serial us80a_pernum), punct(_)
save "Replication_data_workingfile.dta", replace

* Create unique mother IDs
drop if us80a_momloc == 0 //leaving only the children who have a mom
drop personid
egen personid = concat (us80a_serial us80a_momloc), punct(_) // create a new personid for moms only
duplicates drop personid, force
keep us80a_serial personid
save "Replication_data_motheronly.dta", replace

* Merge mothers' data with mothers' person IDs
merge 1:1 personid using "Replication_data_workingfile.dta", force
drop if _merge != 3
drop if us80a_age < 21 | us80a_age > 35 
gen us80a_chborn_new = (us80a_chborn - 1)
drop if (us80a_chborn_new != us80a_nchild) 
drop if us80a_nchild < 2 

save "Replication_data_motheronly.dta", replace




*Part 2: Merge fathers---------------------------------------------------------*
* Create unique father IDs (serial + sploc = fathers personid)
use "Replication_data_workingfile.dta", clear
drop if us80a_sploc_new == "0" | us80a_sex != 1 //only keep male with spouse
drop personid
egen personid = concat (us80a_serial us80a_sploc_new), punct(_) //personid matched later will be the father's data
keep personid us80a_age us80a_agemarr us80a_birthqtr us80a_classwkr us80a_wkswork1 us80a_uhrswork us80a_incwage us80a_incbus us80a_marst us80a_marrno us80a_marrqtr us80a_qbirthmo

*rename father's variables
rename (us80a_age us80a_agemarr us80a_birthqtr us80a_classwkr us80a_wkswork1 us80a_uhrswork us80a_incwage us80a_incbus us80a_marst us80a_marrno us80a_marrqtr) (age_father us80a_agemarr_father us80a_birthqtr_father us80a_classwkr_father us80a_wkswork1_father us80a_uhrswork_father us80a_incwage_father us80a_incbus_father us80a_marst_father us80a_marrno_father us80a_marrqtr_father)
save "Replication_data_father.dta", replace

* Import fathers data to mothers' data.
use "Replication_data_motheronly.dta", clear
drop _merge 
merge 1:1 personid using "Replication_data_father.dta", force
drop if _merge == 2 // drop unmatched fathers
save "Replication_data_motheronly.dta", replace




*Part 3: Merge children--------------------------------------------------------*
* Create children ID (pernum + momloc = mother's personid)
use "Replication_data_workingfile.dta", clear
drop if us80a_momloc == 0 | us80a_momrule != 1
drop personid
egen personid = concat (us80a_serial us80a_momloc), punct(_)
keep personid us80a_sex us80a_age us80a_birthqtr us80a_qage us80a_qsex us80a_qbirthmo parrule
rename (us80a_sex us80a_age us80a_birthqtr us80a_qage us80a_qsex us80a_qbirthmo parrule) (sex_child age_child us80a_birthqtr_child us80a_qage_child us80a_qsex_child us80a_qbirthmo_child parrule_child)

save "Replication_data_children.dta", replace

* Import children's data to mothers data.*
use "Replication_data_motheronly.dta", clear
drop _merge // drop existing merge variable
merge 1:m personid using "Replication_data_children.dta", force
drop if _merge != 3
destring us80a_serial, replace

* Sort child age by household serial number
gsort us80a_serial - age_child
by us80a_serial: generate child_order = _n

* Drop if number of child born doesn't match with the actual
by us80a_serial: generate actual_num_child = _N //check
drop if actual_num_child < 2
drop if us80a_chborn_new != actual_num_child

* Reshape 
drop _merge
reshape wide age_child sex_child us80a_birthqtr_child us80a_qage_child us80a_qsex_child us80a_qbirthmo_child parrule_child , i(us80a_serial) j(child_order)

* Child age restriction
drop if age_child2 < 1
drop if age_child1 > 17

* The reported values of age and sex of their two oldest children were not allocated by the US census
drop if (us80a_qage_child1 != 0) | (us80a_qage_child2 != 0) | (us80a_qsex_child1 != 0) | (us80a_qsex_child2 != 0) | (us80a_qbirthmo_child1 != 0) | (us80a_qbirthmo_child1 != 0)

* Creating "Age at First Birth" variable for moms and dads
gen age_firstbirth = age - age_child1
gen age_firstbirth_father = age_father - age_child1

save "Replication_data_motheronly.dta", replace



* Part 4: Married Couple Restriction ------------------------------------------*
* Married at the time of first birth - couple
gen marr_beforebirth = 0
replace marr_beforebirth = 1 if (us80a_agemarr < age_firstbirth)

* Marriage criteria
gen married = ((us80a_marst == 1) & (us80a_marst_father == 1) & (marr_beforebirth == 1) & (us80a_marrno == 1))
sum married if married == 1

* Create child dummies
gen morethantwo = (actual_num_child > 2)
gen boyfirst = (sex_child1 == 1)
gen boysecond = (sex_child2 == 1)
gen twoboys = (sex_child1 == 1 & sex_child2 == 1)
gen twogirls = (sex_child1 == 2 & sex_child2 == 2)
gen twoboysgirls = (twoboys == 1 | twogirls == 1)
gen samesex = (sex_child1 == sex_child2)
gen twins = ((age_child2 == age_child3) & (us80a_birthqtr_child2 == us80a_birthqtr_child3)) 

* Create labor dummies - mothers
gen labor_income_1995 = (us80a_incwage + us80a_incbus) * 2.099173554
gen workedforpay = (us80a_wkswork1 > 0)
gen us80a_ftotinc_1995 = us80a_ftotinc * 2.099173554
gen ln_us80a_ftotinc_1995 = ln(max(us80a_ftotinc_1995,1))
replace us80a_uhrswork = 0 if workedforpay == 0
gen non_wifeincome = us80a_ftotinc_1995 - labor_income_1995 
gen ln_non_wifeincome = ln(max(non_wifeincome,1))

* Create labor dummies - fathers
gen labor_income_1995_father = (us80a_incwage_father + us80a_incbus_father)* 2.099173554
gen workedforpay_father = (us80a_wkswork1_father > 0)
replace us80a_uhrswork_father = 0 if workedforpay_father == 0
  
* Create race dummies
gen white = (us80a_race == 1)
gen hispanic = (us80a_race == 2)
gen black = (us80a_race == 3)
gen other_race = (us80a_race > 3)

save "Replication_data_motheronly.dta", replace



 
* Table 2
* 1) All Women
estpost sum us80a_chborn_new morethantwo boyfirst boysecond twoboys twogirls samesex twins age age_firstbirth workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 us80a_ftotinc_1995
esttab using Table2.csv, cells("mean sd") noobs label ti("All Women") replace

* 2) Married Women
estpost sum us80a_chborn_new morethantwo boyfirst boysecond twoboys twogirls samesex twins age age_firstbirth workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 us80a_ftotinc_1995 non_wifeincome if married == 1
esttab using Table2.csv, cells("mean sd") noobs label ti("Married Women") append

*3) Husbands
estpost sum age_father age_firstbirth_father workedforpay_father us80a_wkswork1_father us80a_uhrswork_father labor_income_1995_father if married == 1
esttab using Table2.csv, cells("mean sd") noobs label ti("Married Women") append




* Table 6: 2SLS first stage
reg morethantwo samesex
outreg2 using table6.xls, keep(samesex) nocon ctitle(Column 1) replace

reg morethantwo boyfirst boysecond samesex age age_firstbirth black hispanic other_race 
outreg2 using table6.xls, keep(boyfirst boysecond samesex) nocon ctitle(Column 2) append

reg morethantwo boyfirst twoboys twogirls age age_firstbirth black hispanic other_race 
outreg2 using table6.xls, keep(boyfirst twoboys twogirls) nocon ctitle(Column 3) append

reg morethantwo samesex if married == 1
outreg2 using table6.xls, keep(samesex) nocon ctitle(Column 4) append

reg morethantwo boyfirst boysecond samesex age age_firstbirth black hispanic other_race if married == 1
outreg2 using table6.xls, keep(boyfirst boysecond samesex) nocon ctitle(Column 5) append

reg morethantwo boyfirst twoboys twogirls age age_firstbirth black hispanic other_race if married == 1
outreg2 using table6.xls, keep(boyfirst twoboys twogirls) nocon ctitle(Column 6) append




* Table 7: IV Regressions
* 1) All women
foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 {
	reg `var' morethantwo age age_firstbirth boyfirst boysecond black hispanic other_race
	outreg2 using table7_allwomen, keep(morethantwo) nocon ctitle(All Women - OLS, `var')
}

foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 {
	ivregress 2sls `var' (morethantwo = samesex) age age_firstbirth boyfirst boysecond black hispanic other_race, r
	outreg2 using table7_allwomen_iv, keep(morethantwo) nocon ctitle(All Women - IV(samesex), `var')
	}
	
foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 {
	ivregress 2sls `var' (morethantwo = twoboysgirls) age age_firstbirth boyfirst black hispanic other_race, r
	outreg2 using table7_allwomen_iv2, keep(morethantwo) nocon ctitle(All Women - IV(twoboysgirls), `var') 
}

* 2) Married Women
foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 ln_non_wifeincome {
	reg `var' morethantwo age age_firstbirth boyfirst boysecond black hispanic other_race if married == 1
	outreg2 using table7_marriedwomen, keep(morethantwo) nocon ctitle(Married Women - OLS, `var')
}

foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 ln_non_wifeincome {
	ivregress 2sls `var' (morethantwo = samesex) age age_firstbirth boyfirst boysecond black hispanic other_race if married == 1, r
	outreg2 using table7_marriedwomen_iv, keep(morethantwo) nocon ctitle(Married Women - IV(samesex), `var')
	}

foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 ln_non_wifeincome {
	ivregress 2sls `var' (morethantwo = twoboysgirls) age age_firstbirth boyfirst black hispanic other_race if married == 1, r
	outreg2 using table7_marriedwomen_iv2, keep(morethantwo) nocon ctitle(Married Women - IV(twoboysgirls), `var') 
}

* 3) Husbands of Married Women
foreach var of varlist workedforpay_father us80a_wkswork1_father us80a_uhrswork_father labor_income_1995_father {
	reg `var' morethantwo age age_firstbirth boyfirst boysecond black hispanic other_race if married == 1
	outreg2 using table7_marriedmen, keep(morethantwo) nocon ctitle(Married Husbands - OLS, `var')
}

foreach var of varlist workedforpay_father us80a_wkswork1_father us80a_uhrswork_father labor_income_1995_father {
	ivregress 2sls `var' (morethantwo = samesex) age age_firstbirth boyfirst boysecond black hispanic other_race if married == 1, r
	outreg2 using table7_marriedmen_iv, keep(morethantwo) nocon ctitle(Married Husbands, IV(samesex), `var')
	}

foreach var of varlist workedforpay_father us80a_wkswork1_father us80a_uhrswork_father labor_income_1995_father {
	ivregress 2sls `var' (morethantwo = twoboysgirls) age age_firstbirth boyfirst black hispanic other_race if married == 1, r
	outreg2 using table7_marriedmen_iv2, keep(morethantwo) nocon ctitle(Married Husbands, IV(twoboysgirls), `var') 
}





* Additional Results - Heterogeneous treatment effect of having more children on labor supply for black women vs non-black women
gen morethantwo_black = (morethantwo == 1) & (black == 1)
gen samesex_black = (samesex == 1) & (black == 1)
gen twoboysgirls_black = (twoboysgirls == 1) & (black == 1)

* 1) All women
foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 {
	ivregress 2sls `var' (morethantwo morethantwo_black = samesex samesex_black) age age_firstbirth boyfirst boysecond black hispanic other_race, r
	outreg2 using table_new_allwomen_iv, keep(morethantwo morethantwo_black) nocon ctitle(All Women - IV(samesex, samesex_black), `var')
}

foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 {
	ivregress 2sls `var' (morethantwo morethantwo_black = twoboysgirls twoboysgirls_black) age age_firstbirth boyfirst black hispanic other_race, r
	outreg2 using table_new_allwomen_iv2, keep(morethantwo morethantwo_black) nocon ctitle(All Women - IV(twoboysgirls, twoboysgirls_black), `var') 
}

* 2) Married women
foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 {
	ivregress 2sls `var' (morethantwo morethantwo_black = samesex samesex_black) age age_firstbirth boyfirst boysecond black hispanic other_race if married == 1, r
	outreg2 using table_new_marriedwomen_iv, keep(morethantwo morethantwo_black) nocon ctitle(All Women - IV(samesex, samesex_black), `var')
}

foreach var of varlist workedforpay us80a_wkswork1 us80a_uhrswork labor_income_1995 ln_us80a_ftotinc_1995 {
	ivregress 2sls `var' (morethantwo morethantwo_black = twoboysgirls twoboysgirls_black) age age_firstbirth boyfirst black hispanic other_race if married == 1, r
	outreg2 using table_new_marriedwomen_iv2, keep(morethantwo morethantwo_black) nocon ctitle(All Women - IV(twoboysgirls, twoboysgirls_black), `var') 
}

capture log close


