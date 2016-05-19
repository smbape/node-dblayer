/*==============================================================*/
/* DBMS name:      MySQL 5.0                                    */
/* Created on:     19/05/2016 22:22:10                          */
/*==============================================================*/


drop table if exists `ACTIONS`;

drop table if exists `BASIC_DATA`;

drop table if exists `CLASS_A`;

drop table if exists `CLASS_B`;

drop table if exists `CLASS_C`;

drop table if exists `CLASS_D`;

drop table if exists `CLASS_E`;

drop table if exists `CLASS_F`;

drop table if exists `CLASS_G`;

drop table if exists `CLASS_H`;

drop table if exists `CLASS_I`;

drop table if exists `COUNTRIES`;

drop table if exists `DEFAULT_PRIVILEDGES`;

drop table if exists `DELEGATES`;

drop table if exists `FOLDER`;

drop table if exists `LANGUAGES`;

drop table if exists `PRIVILEDGES`;

drop table if exists `PROPERTIES`;

drop table if exists `RESOURCE`;

drop table if exists `TRANSLATIONS`;

drop table if exists `USERS`;

drop table if exists `WORKSPACE`;

/*==============================================================*/
/* Table: ACTIONS                                               */
/*==============================================================*/
create table `ACTIONS`
(
   `ACT_ID`               int(8) not null auto_increment,
   `ACT_CODE`             varchar(63) not null,
   primary key (`ACT_ID`)
);

/*==============================================================*/
/* Table: BASIC_DATA                                            */
/*==============================================================*/
create table `BASIC_DATA`
(
   `DAT_ID`               int(8) not null auto_increment,
   `AOR_ID`               int(8),
   `DOR_ID`               int(8),
   `OOR_ID`               int(8),
   `DAT_CDATE`            datetime not null,
   `DAT_MDATE`            datetime,
   `DAT_VERSION`          varchar(10) not null,
   primary key (`DAT_ID`)
);

/*==============================================================*/
/* Table: CLASS_A                                               */
/*==============================================================*/
create table `CLASS_A`
(
   `A_ID`                 int(8) not null auto_increment,
   `PROP_A1`              varchar(32),
   `PROP_A2`              varchar(32),
   `PROP_A3`              varchar(32),
   `CREATION_DATE`        datetime not null,
   `MODIFICATION_DATE`    datetime not null,
   `VERSION`              varchar(10) not null,
   primary key (`A_ID`)
);

/*==============================================================*/
/* Table: CLASS_B                                               */
/*==============================================================*/
create table `CLASS_B`
(
   `A_ID`                 int(8) not null,
   `PROP_B1`              varchar(32),
   `PROP_B2`              varchar(32),
   `PROP_B3`              varchar(32),
   primary key (`A_ID`)
);

/*==============================================================*/
/* Table: CLASS_C                                               */
/*==============================================================*/
create table `CLASS_C`
(
   `C_ID`                 int(8) not null auto_increment,
   `PROP_C1`              varchar(32),
   `PROP_C2`              varchar(32),
   `PROP_C3`              varchar(32),
   primary key (`C_ID`)
);

/*==============================================================*/
/* Table: CLASS_D                                               */
/*==============================================================*/
create table `CLASS_D`
(
   `A_ID`                 int(8) not null,
   `C_ID`                 int(8) not null,
   `PROP_D1`              varchar(32),
   `PROP_D2`              varchar(32),
   `PROP_D3`              varchar(32),
   primary key (`A_ID`)
);

/*==============================================================*/
/* Table: CLASS_E                                               */
/*==============================================================*/
create table `CLASS_E`
(
   `A_ID`                 int(8) not null,
   `C_ID`                 int(8) not null,
   `PROP_E1`              varchar(32),
   `PROP_E2`              varchar(32),
   `PROP_E3`              varchar(32),
   primary key (`A_ID`)
);

/*==============================================================*/
/* Table: CLASS_F                                               */
/*==============================================================*/
create table `CLASS_F`
(
   `C_ID`                 int(8) not null,
   `A_ID`                 int(8),
   `CLA_A_ID`             int(8),
   `PROP_F1`              varchar(32),
   `PROP_F2`              varchar(32),
   `PROP_F3`              varchar(32),
   primary key (`C_ID`)
);

/*==============================================================*/
/* Table: CLASS_G                                               */
/*==============================================================*/
create table `CLASS_G`
(
   `G_ID`                 int(8) not null auto_increment,
   `PROP_G1`              varchar(32),
   `PROP_G2`              varchar(32),
   `PROP_G3`              varchar(32),
   primary key (`G_ID`),
   unique key `UK_CLASS_G` (`PROP_G1`, `PROP_G2`)
);

/*==============================================================*/
/* Table: CLASS_H                                               */
/*==============================================================*/
create table `CLASS_H`
(
   `G_ID`                 int(8) not null,
   `A_ID`                 int(8) not null,
   `PROP_H1`              varchar(32),
   `PROP_H2`              varchar(32),
   `PROP_H3`              varchar(32)
);

/*==============================================================*/
/* Table: CLASS_I                                               */
/*==============================================================*/
create table `CLASS_I`
(
   `G_ID`                 int(8) not null,
   primary key (`G_ID`)
);

/*==============================================================*/
/* Table: COUNTRIES                                             */
/*==============================================================*/
create table `COUNTRIES`
(
   `CRY_ID`               int(8) not null auto_increment,
   `LPR_ID`               int(8),
   `CRY_CODE`             varchar(63) not null,
   primary key (`CRY_ID`),
   unique key `UK_CRY_CODE` (`CRY_CODE`)
);

/*==============================================================*/
/* Table: DEFAULT_PRIVILEDGES                                   */
/*==============================================================*/
create table `DEFAULT_PRIVILEDGES`
(
   `DAT_ID`               int(8) not null,
   `ACT_ID`               int(8) not null,
   primary key (`DAT_ID`, `ACT_ID`)
);

/*==============================================================*/
/* Table: DELEGATES                                             */
/*==============================================================*/
create table `DELEGATES`
(
   `DAT_ID`               int(8) not null,
   `DGT_ID`               int(8) not null,
   primary key (`DAT_ID`, `DGT_ID`)
);

/*==============================================================*/
/* Table: FOLDER                                                */
/*==============================================================*/
create table `FOLDER`
(
   `DAT_ID`               int(8) not null,
   primary key (`DAT_ID`)
);

/*==============================================================*/
/* Table: LANGUAGES                                             */
/*==============================================================*/
create table `LANGUAGES`
(
   `LNG_ID`               int(8) not null auto_increment,
   `LPR_ID`               int(8),
   `LNG_CODE`             varchar(31) not null,
   `LNG_KEY`              varchar(31),
   `LNG_LABEL`            varchar(63),
   primary key (`LNG_ID`),
   unique key `UK_LNG_CODE` (`LNG_CODE`)
);

/*==============================================================*/
/* Table: PRIVILEDGES                                           */
/*==============================================================*/
create table `PRIVILEDGES`
(
   `DAT_ID`               int(8) not null,
   `ACT_ID`               int(8) not null,
   primary key (`DAT_ID`, `ACT_ID`)
);

/*==============================================================*/
/* Table: PROPERTIES                                            */
/*==============================================================*/
create table `PROPERTIES`
(
   `LPR_ID`               int(8) not null auto_increment,
   `LPR_CODE`             varchar(63) not null,
   primary key (`LPR_ID`),
   unique key `UK_LPR_CODE` (`LPR_CODE`)
);

/*==============================================================*/
/* Table: RESOURCE                                              */
/*==============================================================*/
create table `RESOURCE`
(
   `DAT_ID`               int(8) not null,
   `RSC_NAME`             varchar(63) not null,
   `RSC_PATH`             varchar(255) not null,
   primary key (`DAT_ID`),
   unique key `UK_RESOURCE_PATH` (`RSC_PATH`)
);

/*==============================================================*/
/* Table: TRANSLATIONS                                          */
/*==============================================================*/
create table `TRANSLATIONS`
(
   `LPR_ID`               int(8) not null,
   `LNG_ID`               int(8) not null,
   `TRL_VALUE`            varchar(1024),
   primary key (`LPR_ID`, `LNG_ID`)
);

/*==============================================================*/
/* Table: USERS                                                 */
/*==============================================================*/
create table `USERS`
(
   `DAT_ID`               int(8) not null,
   `CRY_ID`               int(8),
   `LNG_ID`               int(8),
   `USE_NAME`             varchar(63) not null,
   `USE_FIRST_NAME`       varchar(255),
   `USE_EMAIL`            varchar(63) not null,
   `USE_LOGIN`            varchar(31) not null,
   `USE_PASSWORD`         varchar(255),
   `USE_OCCUPATION`       varchar(255),
   `USE_IP`               varchar(63),
   primary key (`DAT_ID`),
   unique key `UK_USE_EMAIL` (`USE_EMAIL`),
   unique key `UK_USE_LOGIN` (`USE_LOGIN`)
);

/*==============================================================*/
/* Table: WORKSPACE                                             */
/*==============================================================*/
create table `WORKSPACE`
(
   `DAT_ID`               int(8) not null,
   `WKS_NAME`             varchar(63) not null,
   primary key (`DAT_ID`),
   unique key `UK_WKS_NAME` (`WKS_NAME`)
);

alter table `BASIC_DATA` add constraint `FK_AUTHOR` foreign key (`AOR_ID`)
      references `USERS` (`DAT_ID`) on delete restrict on update restrict;

alter table `BASIC_DATA` add constraint `FK_DELEGATOR` foreign key (`DOR_ID`)
      references `USERS` (`DAT_ID`) on delete restrict on update restrict;

alter table `BASIC_DATA` add constraint `FK_OPERATOR` foreign key (`OOR_ID`)
      references `USERS` (`DAT_ID`) on delete restrict on update restrict;

alter table `CLASS_B` add constraint `FK_INHERITANCE_1` foreign key (`A_ID`)
      references `CLASS_A` (`A_ID`) on delete restrict on update restrict;

alter table `CLASS_D` add constraint `FK_INHERITANCE_3` foreign key (`A_ID`)
      references `CLASS_A` (`A_ID`) on delete restrict on update restrict;

alter table `CLASS_D` add constraint `FK_RELATIONSHIP_1` foreign key (`C_ID`)
      references `CLASS_C` (`C_ID`) on delete restrict on update restrict;

alter table `CLASS_E` add constraint `FK_INHERITANCE_4` foreign key (`A_ID`)
      references `CLASS_B` (`A_ID`) on delete restrict on update restrict;

alter table `CLASS_E` add constraint `FK_RELATIONSHIP_2` foreign key (`C_ID`)
      references `CLASS_C` (`C_ID`) on delete restrict on update restrict;

alter table `CLASS_F` add constraint `FK_INHERITANCE_5` foreign key (`C_ID`)
      references `CLASS_C` (`C_ID`) on delete restrict on update restrict;

alter table `CLASS_F` add constraint `FK_RELATIONSHIP_3` foreign key (`A_ID`)
      references `CLASS_D` (`A_ID`) on delete restrict on update restrict;

alter table `CLASS_F` add constraint `FK_RELATIONSHIP_4` foreign key (`CLA_A_ID`)
      references `CLASS_E` (`A_ID`) on delete restrict on update restrict;

alter table `CLASS_H` add constraint `FK_RELATIONSHIP_5` foreign key (`G_ID`)
      references `CLASS_G` (`G_ID`) on delete restrict on update restrict;

alter table `CLASS_H` add constraint `FK_RELATIONSHIP_6` foreign key (`A_ID`)
      references `CLASS_D` (`A_ID`) on delete restrict on update restrict;

alter table `CLASS_I` add constraint `FK_INHERITANCE_6` foreign key (`G_ID`)
      references `CLASS_G` (`G_ID`) on delete restrict on update restrict;

alter table `COUNTRIES` add constraint `FK_CRY_LPR` foreign key (`LPR_ID`)
      references `PROPERTIES` (`LPR_ID`) on delete restrict on update restrict;

alter table `DEFAULT_PRIVILEDGES` add constraint `FK_ACT_DFT_PRV` foreign key (`ACT_ID`)
      references `ACTIONS` (`ACT_ID`) on delete restrict on update restrict;

alter table `DEFAULT_PRIVILEDGES` add constraint `FK_FOL_DFT_PRV` foreign key (`DAT_ID`)
      references `FOLDER` (`DAT_ID`) on delete restrict on update restrict;

alter table `DELEGATES` add constraint `FK_DELEGATES` foreign key (`DGT_ID`)
      references `USERS` (`DAT_ID`) on delete restrict on update restrict;

alter table `DELEGATES` add constraint `FK_ISDELEGATE` foreign key (`DAT_ID`)
      references `USERS` (`DAT_ID`) on delete restrict on update restrict;

alter table `FOLDER` add constraint `FK_FOLDER_RESOURCE` foreign key (`DAT_ID`)
      references `RESOURCE` (`DAT_ID`) on delete restrict on update restrict;

alter table `LANGUAGES` add constraint `FK_LNG_LPR` foreign key (`LPR_ID`)
      references `PROPERTIES` (`LPR_ID`) on delete restrict on update restrict;

alter table `PRIVILEDGES` add constraint `FK_ACT_PRV` foreign key (`ACT_ID`)
      references `ACTIONS` (`ACT_ID`) on delete restrict on update restrict;

alter table `PRIVILEDGES` add constraint `FK_RSC_PRV` foreign key (`DAT_ID`)
      references `RESOURCE` (`DAT_ID`) on delete restrict on update restrict;

alter table `RESOURCE` add constraint `FK_RSC_DAT` foreign key (`DAT_ID`)
      references `BASIC_DATA` (`DAT_ID`) on delete restrict on update restrict;

alter table `TRANSLATIONS` add constraint `FK_LNG_TRL` foreign key (`LNG_ID`)
      references `LANGUAGES` (`LNG_ID`) on delete restrict on update restrict;

alter table `TRANSLATIONS` add constraint `FK_LPR_TRL` foreign key (`LPR_ID`)
      references `PROPERTIES` (`LPR_ID`) on delete restrict on update restrict;

alter table `USERS` add constraint `FK_USR_CRY` foreign key (`CRY_ID`)
      references `COUNTRIES` (`CRY_ID`) on delete restrict on update restrict;

alter table `USERS` add constraint `FK_USR_LNG` foreign key (`LNG_ID`)
      references `LANGUAGES` (`LNG_ID`) on delete restrict on update restrict;

alter table `USERS` add constraint `FK_USR_PRS` foreign key (`DAT_ID`)
      references `BASIC_DATA` (`DAT_ID`) on delete restrict on update restrict;

alter table `WORKSPACE` add constraint `FK_WORKSPACE_DATA` foreign key (`DAT_ID`)
      references `BASIC_DATA` (`DAT_ID`) on delete restrict on update restrict;

