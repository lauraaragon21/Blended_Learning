--use @ variables if running in sql server user $ variables if running in Pentaho
--DECLARE @REPORTDATE DATE;

--SET @REPORTDATE = CONVERT(DATE, '${ReportDate}',121);

WITH ST_MEDIAN_MINUTES (STUID,MINS,REPORTDATE,ROWNUM,COUNTWEEKS,TEACHER_NAME) AS --THIS SECTION CREATES A TEMP TABLE WITH USAGE VALUES FOR EACH STUDENT
(
	SELECT 
	SCHOOL_STUDENT_ID,
	CAST(MINUTES_LOGGED_LAST_WEEK AS float) MINS,
	REPORTDATE,
	ROW_NUMBER() OVER (PARTITION BY TEACHER_NAME,REPORTDATE ORDER BY CAST(MINUTES_LOGGED_LAST_WEEK AS float)) ROW_NUM,
	COUNT(REPORTDATE) OVER (PARTITION BY TEACHER_NAME,REPORTDATE) NUM_RECORDS
	,TEACHER_NAME
	FROM [CUSTOM].[INSTRUCTION_STMATH_LJ]
	WHERE REPORTDATE = '${ReportDate}'--@REPORTDATE--between '2016-08-01' and @REPORTDATE
	AND MINUTES_LOGGED_LAST_WEEK IS NOT NULL
)


INSERT INTO custom.Instruction_Blended_Fact_v2 (PLATFORMKEY,STUDENTKEY,SCHOOLKEY,DATE,SUBJECT,PROGRESS1,PROGRESS2,MASTERY,USAGE,ALT_USAGE,USAGE_OUTLIER,ALERTS,HAS_ALERTS,MATERIAL_GRADELEVEL,TEACHER_NAME)
SELECT
1 AS PLATFORMKEY
,DSTU.STUDENTKEY
,SCHOOLKEY
,ST.REPORTDATE
,0 AS SUBJECT
,CASE --if actual grade level is less than material grade level than add 100*(grade level difference) to progress
	WHEN (CASE 
		WHEN ST.GCD LIKE 'First%' then 1
		WHEN ST.GCD LIKE 'Second%' then 2
		WHEN ST.GCD LIKE 'Third%' then 3
		WHEN ST.GCD LIKE 'Fourth%' then 4
		WHEN ST.GCD LIKE 'Fifth%' then 5
		WHEN ST.GCD LIKE 'Sixth%' then 6
		WHEN ST.GCD LIKE 'Seventh%' then 7
		WHEN ST.GCD LIKE 'Eighth%' then 8
		ELSE Null
	      END) > s.grade_level 
	   THEN ((CASE 
			WHEN ST.GCD LIKE 'First%' then 1
			WHEN ST.GCD LIKE 'Second%' then 2
			WHEN ST.GCD LIKE 'Third%' then 3
			WHEN ST.GCD LIKE 'Fourth%' then 4
			WHEN ST.GCD LIKE 'Fifth%' then 5
			WHEN ST.GCD LIKE 'Sixth%' then 6
			WHEN ST.GCD LIKE 'Seventh%' then 7
			WHEN ST.GCD LIKE 'Eighth%' then 8
			ELSE Null
		 END) - s.grade_level)*100.0 + ST.K_5_PROGRESS 
	ELSE ST.K_5_PROGRESS END AS PROGRESS --% PROGRESS YTD
,CASE
	WHEN CAST(ST.K_5_PROGRESS AS FLOAT) < CAST(ST_LAG.K_5_PROGRESS AS FLOAT)
	THEN 100-CAST(ST_LAG.K_5_PROGRESS AS FLOAT) + CAST(ST.K_5_PROGRESS AS FLOAT)
	ELSE COALESCE(CAST(ST.K_5_PROGRESS AS FLOAT)-CAST(ST_LAG.K_5_PROGRESS AS FLOAT),ST.K_5_PROGRESS) 
 END AS PROGRESS2 --CHANGE IN PROGRESS EACH WEEK
,COALESCE(CAST(ST.K_5_PROGRESS AS FLOAT)/NULLIF((CAST(ST.ALT_SRC_TIME AS FLOAT)/30),0),0) AS MASTERY--EFFICIENCY AS MASTERY
,CASE --IF USAGE IS GREATER THAN 300 MINUTES IN A GIVEN WEEK, THEN REPLACE WITH THE MEDIAN USAGE FROM THAT CLASS AND REPORTDATE
	WHEN ST.MINUTES_LOGGED_LAST_WEEK > 300 THEN 
		(SELECT -- THIS SUBQUERY USES THE TEMP TABLE TO CALCULATE THE MEDIAN, BASED ON TUTORIAL FOUND HERE: http://blogs.lessthandot.com/index.php/datamgmt/dbprogramming/it-s-hard-to-be/
		 AVG(MINS)
		 FROM ST_MEDIAN_MINUTES
		 WHERE 1=1
		 AND ST_MEDIAN_MINUTES.TEACHER_NAME = ST.TEACHER_NAME
		 AND ST_MEDIAN_MINUTES.REPORTDATE = ST.REPORTDATE
		 )
	ELSE
		COALESCE(ST.MINUTES_LOGGED_LAST_WEEK,0) 
 END AS USAGE
--,CAST(ST.ALT_SRC_TIME AS INT)-CAST(LAG(ST.ALT_SRC_TIME,1,0) OVER ( PARTITION BY DSTU.STUDENTKEY ORDER BY DSTU.STUDENTKEY, ST.REPORTDATE) AS INT) AS ALT_USAGE --CHANGE IN ALT_SRC_TIME EACH WEEK
,COALESCE(CAST(ST.ALT_SRC_TIME AS INT) - CAST(ST_LAG.ALT_SRC_TIME AS INT),ST.ALT_SRC_TIME) AS ALT_USAGE
,CASE WHEN ST.MINUTES_LOGGED_LAST_WEEK>300 THEN 1 ELSE 0 END USAGE_OUTLIER
,NULL AS ALERTS
,CASE 
	WHEN ST.CUR_HURDLE_NUM_TRIES>9 THEN 1 
	ELSE 0 
 END AS HAS_ALERTS
,CASE 
	WHEN ST.GCD LIKE 'First%' then 1
	WHEN ST.GCD LIKE 'Second%' then 2
	WHEN ST.GCD LIKE 'Third%' then 3
	WHEN ST.GCD LIKE 'Fourth%' then 4
	WHEN ST.GCD LIKE 'Fifth%' then 5
	WHEN ST.GCD LIKE 'Sixth%' then 6
	WHEN ST.GCD LIKE 'Seventh%' then 7
	WHEN ST.GCD LIKE 'Eighth%' then 8
	ELSE Null
 END MATERIAL_GRADELEVEL,
ST.TEACHER_NAME 
FROM [CUSTOM].[INSTRUCTION_STMATH_LJ] ST
JOIN [DW].[DW_DIMSTUDENT] DSTU ON DSTU.SYSTEMSTUDENTID=ST.SCHOOL_STUDENT_ID
JOIN [CUSTOM].[CUSTOM_STUDENTBRIDGE] B ON B.SYSTEMSTUDENTID=DSTU.SYSTEMSTUDENTID
JOIN [POWERSCHOOL].[POWERSCHOOL_STUDENTS] S ON S.STUDENT_NUMBER=B.STUDENT_NUMBER
JOIN [DW].[DW_DIMSCHOOL] DSCH ON DSCH.SYSTEMSCHOOLID=S.SCHOOLID
LEFT JOIN [CUSTOM].[INSTRUCTION_STMATH_LJ] ST_LAG ON ST_LAG.SCHOOL_STUDENT_ID = ST.SCHOOL_STUDENT_ID AND DATEADD(DD,7,ST_LAG.REPORTDATE) = ST.REPORTDATE
WHERE DSCH.SYSTEMSCHOOLID!='-----'
AND ST.REPORTDATE = '${ReportDate}'--@REPORTDATE
--order by cast(ST.K_5_PROGRESS as float)  desc
--and studentkey = 7461
--ORDER BY TEACHER_NAME,REPORTDATE
;
