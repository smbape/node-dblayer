/*==============================================================*/
/* DBMS name:      PostgreSQL 9.x                               */
/* Created on:     19/05/2016 21:33:42                          */
/*==============================================================*/


drop index if exists "ACTIONS_PK" cascade;

drop table if exists "ACTIONS" cascade;

drop index if exists "OPERATOR_FK" cascade;

drop index if exists "DELEGATOR_FK" cascade;

drop index if exists "AUTHOR_FK" cascade;

drop index if exists "BASIC_DATA_PK" cascade;

drop table if exists "BASIC_DATA" cascade;

drop index if exists "CLASS_A_PK" cascade;

drop table if exists "CLASS_A" cascade;

drop index if exists "CLASS_B_PK" cascade;

drop table if exists "CLASS_B" cascade;

drop index if exists "CLASS_C_PK" cascade;

drop table if exists "CLASS_C" cascade;

drop index if exists "RELATIONSHIP_1_FK" cascade;

drop index if exists "CLASS_D_PK" cascade;

drop table if exists "CLASS_D" cascade;

drop index if exists "RELATIONSHIP_2_FK" cascade;

drop index if exists "CLASS_E_PK" cascade;

drop table if exists "CLASS_E" cascade;

drop index if exists "RELATIONSHIP_4_FK" cascade;

drop index if exists "RELATIONSHIP_3_FK" cascade;

drop index if exists "CLASS_F_PK" cascade;

drop table if exists "CLASS_F" cascade;

drop index if exists "CLASS_G_PK" cascade;

drop table if exists "CLASS_G" cascade;

drop index if exists "RELATIONSHIP_6_FK" cascade;

drop index if exists "RELATIONSHIP_5_FK" cascade;

drop table if exists "CLASS_H" cascade;

drop index if exists "CLASS_I_PK" cascade;

drop table if exists "CLASS_I" cascade;

drop index if exists "CRY_LPR_FK" cascade;

drop index if exists "COUNTRIES_PK" cascade;

drop table if exists "COUNTRIES" cascade;

drop index if exists "ACT_DFT_PRV_FK" cascade;

drop index if exists "FOL_DFT_PRV_FK" cascade;

drop index if exists "DEFAULT_PRIVILEDGES_PK" cascade;

drop table if exists "DEFAULT_PRIVILEDGES" cascade;

drop index if exists "DELEGATES_FK" cascade;

drop index if exists "ISDELEGATE_FK" cascade;

drop index if exists "DELEGATES_PK" cascade;

drop table if exists "DELEGATES" cascade;

drop index if exists "FOLDER_PK" cascade;

drop table if exists "FOLDER" cascade;

drop index if exists "LNG_LPR_FK" cascade;

drop index if exists "LANGUAGES_PK" cascade;

drop table if exists "LANGUAGES" cascade;

drop index if exists "ACT_PRV_FK" cascade;

drop index if exists "RSC_PRV_FK" cascade;

drop index if exists "PRIVILEDGES_PK" cascade;

drop table if exists "PRIVILEDGES" cascade;

drop index if exists "PROPERTIES_PK" cascade;

drop table if exists "PROPERTIES" cascade;

drop index if exists "RESOURCE_PK" cascade;

drop table if exists "RESOURCE" cascade;

drop index if exists "LNG_TRL_FK" cascade;

drop index if exists "LPR_TRL_FK" cascade;

drop index if exists "TRANSLATIONS_PK" cascade;

drop table if exists "TRANSLATIONS" cascade;

drop index if exists "USR_CRY_FK" cascade;

drop index if exists "USR_LNG_FK" cascade;

drop index if exists "USERS_PK" cascade;

drop table if exists "USERS" cascade;

drop index if exists "WORKSPACE_PK" cascade;

drop table if exists "WORKSPACE" cascade;

drop domain if exists "CODE" cascade;

drop domain if exists "COMMENTAIRE" cascade;

drop domain if exists "EMAIL" cascade;

drop domain if exists "LIBELLE_COURT" cascade;

drop domain if exists "LONG_LABEL" cascade;

drop domain if exists "MEDIUM_LABEL" cascade;

drop domain if exists "PHONE" cascade;

drop domain if exists "SHORT_LABEL" cascade;

drop domain if exists "TITLE" cascade;

drop domain if exists "UTCTIME" cascade;

drop domain if exists "VERSION" cascade;

/*==============================================================*/
/* Domain: CODE                                                 */
/*==============================================================*/
create domain "CODE" as VARCHAR(63);

/*==============================================================*/
/* Domain: COMMENTAIRE                                          */
/*==============================================================*/
create domain "COMMENTAIRE" as VARCHAR(1024);

/*==============================================================*/
/* Domain: EMAIL                                                */
/*==============================================================*/
create domain "EMAIL" as VARCHAR(63);

/*==============================================================*/
/* Domain: LIBELLE_COURT                                        */
/*==============================================================*/
create domain "LIBELLE_COURT" as VARCHAR(32);

/*==============================================================*/
/* Domain: LONG_LABEL                                           */
/*==============================================================*/
create domain "LONG_LABEL" as VARCHAR(255);

/*==============================================================*/
/* Domain: MEDIUM_LABEL                                         */
/*==============================================================*/
create domain "MEDIUM_LABEL" as VARCHAR(63);

/*==============================================================*/
/* Domain: PHONE                                                */
/*==============================================================*/
create domain "PHONE" as VARCHAR(31);

/*==============================================================*/
/* Domain: SHORT_LABEL                                          */
/*==============================================================*/
create domain "SHORT_LABEL" as VARCHAR(31);

/*==============================================================*/
/* Domain: TITLE                                                */
/*==============================================================*/
create domain "TITLE" as VARCHAR(255);

/*==============================================================*/
/* Domain: UTCTIME                                              */
/*==============================================================*/
create domain "UTCTIME" as TIMESTAMP;

/*==============================================================*/
/* Domain: VERSION                                              */
/*==============================================================*/
create domain "VERSION" as VARCHAR(10);

/*==============================================================*/
/* Table: ACTIONS                                               */
/*==============================================================*/
create table "ACTIONS" (
   "ACT_ID"               BIGSERIAL            not null,
   "ACT_CODE"             "CODE"                 not null,
   constraint "PK_ACTIONS" primary key ("ACT_ID")
);

/*==============================================================*/
/* Index: ACTIONS_PK                                            */
/*==============================================================*/
create unique index "ACTIONS_PK" on "ACTIONS" (
"ACT_ID"
);

/*==============================================================*/
/* Table: BASIC_DATA                                            */
/*==============================================================*/
create table "BASIC_DATA" (
   "DAT_ID"               BIGSERIAL            not null,
   "AOR_ID"               INT8                 null,
   "DOR_ID"               INT8                 null,
   "OOR_ID"               INT8                 null,
   "DAT_CDATE"            "UTCTIME"              not null,
   "DAT_MDATE"            "UTCTIME"              null,
   "DAT_VERSION"          "VERSION"              not null,
   constraint "PK_BASIC_DATA" primary key ("DAT_ID")
);

/*==============================================================*/
/* Index: BASIC_DATA_PK                                         */
/*==============================================================*/
create unique index "BASIC_DATA_PK" on "BASIC_DATA" (
"DAT_ID"
);

/*==============================================================*/
/* Index: AUTHOR_FK                                             */
/*==============================================================*/
create  index "AUTHOR_FK" on "BASIC_DATA" (
"AOR_ID"
);

/*==============================================================*/
/* Index: DELEGATOR_FK                                          */
/*==============================================================*/
create  index "DELEGATOR_FK" on "BASIC_DATA" (
"DOR_ID"
);

/*==============================================================*/
/* Index: OPERATOR_FK                                           */
/*==============================================================*/
create  index "OPERATOR_FK" on "BASIC_DATA" (
"OOR_ID"
);

/*==============================================================*/
/* Table: CLASS_A                                               */
/*==============================================================*/
create table "CLASS_A" (
   "A_ID"                 BIGSERIAL            not null,
   "PROP_A1"              "LIBELLE_COURT"        null,
   "PROP_A2"              "LIBELLE_COURT"        null,
   "PROP_A3"              "LIBELLE_COURT"        null,
   "CREATION_DATE"        "UTCTIME"              not null,
   "MODIFICATION_DATE"    "UTCTIME"              not null,
   "VERSION"              "VERSION"              not null,
   constraint "PK_CLASS_A" primary key ("A_ID")
);

/*==============================================================*/
/* Index: CLASS_A_PK                                            */
/*==============================================================*/
create unique index "CLASS_A_PK" on "CLASS_A" (
"A_ID"
);

/*==============================================================*/
/* Table: CLASS_B                                               */
/*==============================================================*/
create table "CLASS_B" (
   "A_ID"                 INT8                 not null,
   "PROP_B1"              "LIBELLE_COURT"        null,
   "PROP_B2"              "LIBELLE_COURT"        null,
   "PROP_B3"              "LIBELLE_COURT"        null,
   constraint "PK_CLASS_B" primary key ("A_ID")
);

/*==============================================================*/
/* Index: CLASS_B_PK                                            */
/*==============================================================*/
create unique index "CLASS_B_PK" on "CLASS_B" (
"A_ID"
);

/*==============================================================*/
/* Table: CLASS_C                                               */
/*==============================================================*/
create table "CLASS_C" (
   "C_ID"                 BIGSERIAL            not null,
   "PROP_C1"              "LIBELLE_COURT"        null,
   "PROP_C2"              "LIBELLE_COURT"        null,
   "PROP_C3"              "LIBELLE_COURT"        null,
   constraint "PK_CLASS_C" primary key ("C_ID")
);

/*==============================================================*/
/* Index: CLASS_C_PK                                            */
/*==============================================================*/
create unique index "CLASS_C_PK" on "CLASS_C" (
"C_ID"
);

/*==============================================================*/
/* Table: CLASS_D                                               */
/*==============================================================*/
create table "CLASS_D" (
   "A_ID"                 INT8                 not null,
   "C_ID"                 INT8                 not null,
   "PROP_D1"              "LIBELLE_COURT"        null,
   "PROP_D2"              "LIBELLE_COURT"        null,
   "PROP_D3"              "LIBELLE_COURT"        null,
   constraint "PK_CLASS_D" primary key ("A_ID")
);

/*==============================================================*/
/* Index: CLASS_D_PK                                            */
/*==============================================================*/
create unique index "CLASS_D_PK" on "CLASS_D" (
"A_ID"
);

/*==============================================================*/
/* Index: RELATIONSHIP_1_FK                                     */
/*==============================================================*/
create  index "RELATIONSHIP_1_FK" on "CLASS_D" (
"C_ID"
);

/*==============================================================*/
/* Table: CLASS_E                                               */
/*==============================================================*/
create table "CLASS_E" (
   "A_ID"                 INT8                 not null,
   "C_ID"                 INT8                 not null,
   "PROP_E1"              "LIBELLE_COURT"        null,
   "PROP_E2"              "LIBELLE_COURT"        null,
   "PROP_E3"              "LIBELLE_COURT"        null,
   constraint "PK_CLASS_E" primary key ("A_ID")
);

/*==============================================================*/
/* Index: CLASS_E_PK                                            */
/*==============================================================*/
create unique index "CLASS_E_PK" on "CLASS_E" (
"A_ID"
);

/*==============================================================*/
/* Index: RELATIONSHIP_2_FK                                     */
/*==============================================================*/
create  index "RELATIONSHIP_2_FK" on "CLASS_E" (
"C_ID"
);

/*==============================================================*/
/* Table: CLASS_F                                               */
/*==============================================================*/
create table "CLASS_F" (
   "C_ID"                 INT8                 not null,
   "A_ID"                 INT8                 null,
   "CLA_A_ID"             INT8                 null,
   "PROP_F1"              "LIBELLE_COURT"        null,
   "PROP_F2"              "LIBELLE_COURT"        null,
   "PROP_F3"              "LIBELLE_COURT"        null,
   constraint "PK_CLASS_F" primary key ("C_ID")
);

/*==============================================================*/
/* Index: CLASS_F_PK                                            */
/*==============================================================*/
create unique index "CLASS_F_PK" on "CLASS_F" (
"C_ID"
);

/*==============================================================*/
/* Index: RELATIONSHIP_3_FK                                     */
/*==============================================================*/
create  index "RELATIONSHIP_3_FK" on "CLASS_F" (
"A_ID"
);

/*==============================================================*/
/* Index: RELATIONSHIP_4_FK                                     */
/*==============================================================*/
create  index "RELATIONSHIP_4_FK" on "CLASS_F" (
"CLA_A_ID"
);

/*==============================================================*/
/* Table: CLASS_G                                               */
/*==============================================================*/
create table "CLASS_G" (
   "G_ID"                 BIGSERIAL            not null,
   "PROP_G1"              "LIBELLE_COURT"        null,
   "PROP_G2"              "LIBELLE_COURT"        null,
   "PROP_G3"              "LIBELLE_COURT"        null,
   constraint "PK_CLASS_G" primary key ("G_ID"),
   constraint "UK_CLASS_G" unique ("PROP_G1", "PROP_G2")
);

/*==============================================================*/
/* Index: CLASS_G_PK                                            */
/*==============================================================*/
create unique index "CLASS_G_PK" on "CLASS_G" (
"G_ID"
);

/*==============================================================*/
/* Table: CLASS_H                                               */
/*==============================================================*/
create table "CLASS_H" (
   "G_ID"                 INT8                 not null,
   "A_ID"                 INT8                 not null,
   "PROP_H1"              "LIBELLE_COURT"        null,
   "PROP_H2"              "LIBELLE_COURT"        null,
   "PROP_H3"              "LIBELLE_COURT"        null
);

/*==============================================================*/
/* Index: RELATIONSHIP_5_FK                                     */
/*==============================================================*/
create  index "RELATIONSHIP_5_FK" on "CLASS_H" (
"G_ID"
);

/*==============================================================*/
/* Index: RELATIONSHIP_6_FK                                     */
/*==============================================================*/
create  index "RELATIONSHIP_6_FK" on "CLASS_H" (
"A_ID"
);

/*==============================================================*/
/* Table: CLASS_I                                               */
/*==============================================================*/
create table "CLASS_I" (
   "G_ID"                 INT8                 not null,
   constraint "PK_CLASS_I" primary key ("G_ID")
);

/*==============================================================*/
/* Index: CLASS_I_PK                                            */
/*==============================================================*/
create unique index "CLASS_I_PK" on "CLASS_I" (
"G_ID"
);

/*==============================================================*/
/* Table: COUNTRIES                                             */
/*==============================================================*/
create table "COUNTRIES" (
   "CRY_ID"               BIGSERIAL            not null,
   "LPR_ID"               INT8                 null,
   "CRY_CODE"             "CODE"                 not null,
   constraint "PK_COUNTRIES" primary key ("CRY_ID"),
   constraint "UK_CRY_CODE" unique ("CRY_CODE")
);

/*==============================================================*/
/* Index: COUNTRIES_PK                                          */
/*==============================================================*/
create unique index "COUNTRIES_PK" on "COUNTRIES" (
"CRY_ID"
);

/*==============================================================*/
/* Index: CRY_LPR_FK                                            */
/*==============================================================*/
create  index "CRY_LPR_FK" on "COUNTRIES" (
"LPR_ID"
);

/*==============================================================*/
/* Table: DEFAULT_PRIVILEDGES                                   */
/*==============================================================*/
create table "DEFAULT_PRIVILEDGES" (
   "DAT_ID"               INT8                 not null,
   "ACT_ID"               INT8                 not null,
   constraint "PK_DEFAULT_PRIVILEDGES" primary key ("DAT_ID", "ACT_ID")
);

/*==============================================================*/
/* Index: DEFAULT_PRIVILEDGES_PK                                */
/*==============================================================*/
create unique index "DEFAULT_PRIVILEDGES_PK" on "DEFAULT_PRIVILEDGES" (
"DAT_ID",
"ACT_ID"
);

/*==============================================================*/
/* Index: FOL_DFT_PRV_FK                                        */
/*==============================================================*/
create  index "FOL_DFT_PRV_FK" on "DEFAULT_PRIVILEDGES" (
"DAT_ID"
);

/*==============================================================*/
/* Index: ACT_DFT_PRV_FK                                        */
/*==============================================================*/
create  index "ACT_DFT_PRV_FK" on "DEFAULT_PRIVILEDGES" (
"ACT_ID"
);

/*==============================================================*/
/* Table: DELEGATES                                             */
/*==============================================================*/
create table "DELEGATES" (
   "DAT_ID"               INT8                 not null,
   "DGT_ID"               INT8                 not null,
   constraint "PK_DELEGATES" primary key ("DAT_ID", "DGT_ID")
);

/*==============================================================*/
/* Index: DELEGATES_PK                                          */
/*==============================================================*/
create unique index "DELEGATES_PK" on "DELEGATES" (
"DAT_ID",
"DGT_ID"
);

/*==============================================================*/
/* Index: ISDELEGATE_FK                                         */
/*==============================================================*/
create  index "ISDELEGATE_FK" on "DELEGATES" (
"DAT_ID"
);

/*==============================================================*/
/* Index: DELEGATES_FK                                          */
/*==============================================================*/
create  index "DELEGATES_FK" on "DELEGATES" (
"DGT_ID"
);

/*==============================================================*/
/* Table: FOLDER                                                */
/*==============================================================*/
create table "FOLDER" (
   "DAT_ID"               INT8                 not null,
   constraint "PK_FOLDER" primary key ("DAT_ID")
);

/*==============================================================*/
/* Index: FOLDER_PK                                             */
/*==============================================================*/
create unique index "FOLDER_PK" on "FOLDER" (
"DAT_ID"
);

/*==============================================================*/
/* Table: LANGUAGES                                             */
/*==============================================================*/
create table "LANGUAGES" (
   "LNG_ID"               BIGSERIAL            not null,
   "LPR_ID"               INT8                 null,
   "LNG_CODE"             "SHORT_LABEL"          not null,
   "LNG_KEY"              "SHORT_LABEL"          null,
   "LNG_LABEL"            "MEDIUM_LABEL"         null,
   constraint "PK_LANGUAGES" primary key ("LNG_ID"),
   constraint "UK_LNG_CODE" unique ("LNG_CODE")
);

/*==============================================================*/
/* Index: LANGUAGES_PK                                          */
/*==============================================================*/
create unique index "LANGUAGES_PK" on "LANGUAGES" (
"LNG_ID"
);

/*==============================================================*/
/* Index: LNG_LPR_FK                                            */
/*==============================================================*/
create  index "LNG_LPR_FK" on "LANGUAGES" (
"LPR_ID"
);

/*==============================================================*/
/* Table: PRIVILEDGES                                           */
/*==============================================================*/
create table "PRIVILEDGES" (
   "DAT_ID"               INT8                 not null,
   "ACT_ID"               INT8                 not null,
   constraint "PK_PRIVILEDGES" primary key ("DAT_ID", "ACT_ID")
);

/*==============================================================*/
/* Index: PRIVILEDGES_PK                                        */
/*==============================================================*/
create unique index "PRIVILEDGES_PK" on "PRIVILEDGES" (
"DAT_ID",
"ACT_ID"
);

/*==============================================================*/
/* Index: RSC_PRV_FK                                            */
/*==============================================================*/
create  index "RSC_PRV_FK" on "PRIVILEDGES" (
"DAT_ID"
);

/*==============================================================*/
/* Index: ACT_PRV_FK                                            */
/*==============================================================*/
create  index "ACT_PRV_FK" on "PRIVILEDGES" (
"ACT_ID"
);

/*==============================================================*/
/* Table: PROPERTIES                                            */
/*==============================================================*/
create table "PROPERTIES" (
   "LPR_ID"               BIGSERIAL            not null,
   "LPR_CODE"             "CODE"                 not null,
   constraint "PK_PROPERTIES" primary key ("LPR_ID"),
   constraint "UK_LPR_CODE" unique ("LPR_CODE")
);

/*==============================================================*/
/* Index: PROPERTIES_PK                                         */
/*==============================================================*/
create unique index "PROPERTIES_PK" on "PROPERTIES" (
"LPR_ID"
);

/*==============================================================*/
/* Table: RESOURCE                                              */
/*==============================================================*/
create table "RESOURCE" (
   "DAT_ID"               INT8                 not null,
   "RSC_NAME"             "MEDIUM_LABEL"         not null,
   "RSC_PATH"             "LONG_LABEL"           not null,
   constraint "PK_RESOURCE" primary key ("DAT_ID"),
   constraint "UK_RESOURCE_PATH" unique ("RSC_PATH")
);

/*==============================================================*/
/* Index: RESOURCE_PK                                           */
/*==============================================================*/
create unique index "RESOURCE_PK" on "RESOURCE" (
"DAT_ID"
);

/*==============================================================*/
/* Table: TRANSLATIONS                                          */
/*==============================================================*/
create table "TRANSLATIONS" (
   "LPR_ID"               INT8                 not null,
   "LNG_ID"               INT8                 not null,
   "TRL_VALUE"            "COMMENTAIRE"          null,
   constraint "PK_TRANSLATIONS" primary key ("LPR_ID", "LNG_ID")
);

/*==============================================================*/
/* Index: TRANSLATIONS_PK                                       */
/*==============================================================*/
create unique index "TRANSLATIONS_PK" on "TRANSLATIONS" (
"LPR_ID",
"LNG_ID"
);

/*==============================================================*/
/* Index: LPR_TRL_FK                                            */
/*==============================================================*/
create  index "LPR_TRL_FK" on "TRANSLATIONS" (
"LPR_ID"
);

/*==============================================================*/
/* Index: LNG_TRL_FK                                            */
/*==============================================================*/
create  index "LNG_TRL_FK" on "TRANSLATIONS" (
"LNG_ID"
);

/*==============================================================*/
/* Table: USERS                                                 */
/*==============================================================*/
create table "USERS" (
   "DAT_ID"               INT8                 not null,
   "CRY_ID"               INT8                 null,
   "LNG_ID"               INT8                 null,
   "USE_NAME"             "MEDIUM_LABEL"         not null,
   "USE_FIRST_NAME"       "LONG_LABEL"           null,
   "USE_EMAIL"            "EMAIL"                not null,
   "USE_LOGIN"            "SHORT_LABEL"          not null,
   "USE_PASSWORD"         "LONG_LABEL"           null,
   "USE_OCCUPATION"       "LONG_LABEL"           null,
   "USE_IP"               "MEDIUM_LABEL"         null,
   constraint "PK_USERS" primary key ("DAT_ID"),
   constraint "UK_USE_EMAIL" unique ("USE_EMAIL"),
   constraint "UK_USE_LOGIN" unique ("USE_LOGIN")
);

/*==============================================================*/
/* Index: USERS_PK                                              */
/*==============================================================*/
create unique index "USERS_PK" on "USERS" (
"DAT_ID"
);

/*==============================================================*/
/* Index: USR_LNG_FK                                            */
/*==============================================================*/
create  index "USR_LNG_FK" on "USERS" (
"LNG_ID"
);

/*==============================================================*/
/* Index: USR_CRY_FK                                            */
/*==============================================================*/
create  index "USR_CRY_FK" on "USERS" (
"CRY_ID"
);

/*==============================================================*/
/* Table: WORKSPACE                                             */
/*==============================================================*/
create table "WORKSPACE" (
   "DAT_ID"               INT8                 not null,
   "WKS_NAME"             "MEDIUM_LABEL"         not null,
   constraint "PK_WORKSPACE" primary key ("DAT_ID"),
   constraint "UK_WKS_NAME" unique ("WKS_NAME")
);

/*==============================================================*/
/* Index: WORKSPACE_PK                                          */
/*==============================================================*/
create unique index "WORKSPACE_PK" on "WORKSPACE" (
"DAT_ID"
);

alter table "BASIC_DATA"
   add constraint "FK_BASIC_DA_AUTHOR_USERS" foreign key ("AOR_ID")
      references "USERS" ("DAT_ID")
      on delete restrict on update restrict;

alter table "BASIC_DATA"
   add constraint "FK_BASIC_DA_DELEGATOR_USERS" foreign key ("DOR_ID")
      references "USERS" ("DAT_ID")
      on delete restrict on update restrict;

alter table "BASIC_DATA"
   add constraint "FK_BASIC_DA_OPERATOR_USERS" foreign key ("OOR_ID")
      references "USERS" ("DAT_ID")
      on delete restrict on update restrict;

alter table "CLASS_B"
   add constraint "FK_CLASS_B_INHERITAN_CLASS_A" foreign key ("A_ID")
      references "CLASS_A" ("A_ID")
      on delete restrict on update restrict;

alter table "CLASS_D"
   add constraint "FK_CLASS_D_INHERITAN_CLASS_A" foreign key ("A_ID")
      references "CLASS_A" ("A_ID")
      on delete restrict on update restrict;

alter table "CLASS_D"
   add constraint "FK_CLASS_D_RELATIONS_CLASS_C" foreign key ("C_ID")
      references "CLASS_C" ("C_ID")
      on delete restrict on update restrict;

alter table "CLASS_E"
   add constraint "FK_CLASS_E_INHERITAN_CLASS_B" foreign key ("A_ID")
      references "CLASS_B" ("A_ID")
      on delete restrict on update restrict;

alter table "CLASS_E"
   add constraint "FK_CLASS_E_RELATIONS_CLASS_C" foreign key ("C_ID")
      references "CLASS_C" ("C_ID")
      on delete restrict on update restrict;

alter table "CLASS_F"
   add constraint "FK_CLASS_F_INHERITAN_CLASS_C" foreign key ("C_ID")
      references "CLASS_C" ("C_ID")
      on delete restrict on update restrict;

alter table "CLASS_F"
   add constraint "FK_CLASS_F_RELATIONS_CLASS_D" foreign key ("A_ID")
      references "CLASS_D" ("A_ID")
      on delete restrict on update restrict;

alter table "CLASS_F"
   add constraint "FK_CLASS_F_RELATIONS_CLASS_E" foreign key ("CLA_A_ID")
      references "CLASS_E" ("A_ID")
      on delete restrict on update restrict;

alter table "CLASS_H"
   add constraint "FK_CLASS_H_RELATIONS_CLASS_G" foreign key ("G_ID")
      references "CLASS_G" ("G_ID")
      on delete restrict on update restrict;

alter table "CLASS_H"
   add constraint "FK_CLASS_H_RELATIONS_CLASS_D" foreign key ("A_ID")
      references "CLASS_D" ("A_ID")
      on delete restrict on update restrict;

alter table "CLASS_I"
   add constraint "FK_CLASS_I_INHERITAN_CLASS_G" foreign key ("G_ID")
      references "CLASS_G" ("G_ID")
      on delete restrict on update restrict;

alter table "COUNTRIES"
   add constraint "FK_COUNTRIE_CRY_LPR_PROPERTI" foreign key ("LPR_ID")
      references "PROPERTIES" ("LPR_ID")
      on delete restrict on update restrict;

alter table "DEFAULT_PRIVILEDGES"
   add constraint "FK_DEFAULT__ACT_DFT_P_ACTIONS" foreign key ("ACT_ID")
      references "ACTIONS" ("ACT_ID")
      on delete restrict on update restrict;

alter table "DEFAULT_PRIVILEDGES"
   add constraint "FK_DEFAULT__FOL_DFT_P_FOLDER" foreign key ("DAT_ID")
      references "FOLDER" ("DAT_ID")
      on delete restrict on update restrict;

alter table "DELEGATES"
   add constraint "FK_DELEGATE_DELEGATES_USERS" foreign key ("DGT_ID")
      references "USERS" ("DAT_ID")
      on delete restrict on update restrict;

alter table "DELEGATES"
   add constraint "FK_DELEGATE_ISDELEGAT_USERS" foreign key ("DAT_ID")
      references "USERS" ("DAT_ID")
      on delete restrict on update restrict;

alter table "FOLDER"
   add constraint "FK_FOLDER_FOLDER_RE_RESOURCE" foreign key ("DAT_ID")
      references "RESOURCE" ("DAT_ID")
      on delete restrict on update restrict;

alter table "LANGUAGES"
   add constraint "FK_LANGUAGE_LNG_LPR_PROPERTI" foreign key ("LPR_ID")
      references "PROPERTIES" ("LPR_ID")
      on delete restrict on update restrict;

alter table "PRIVILEDGES"
   add constraint "FK_PRIVILED_ACT_PRV_ACTIONS" foreign key ("ACT_ID")
      references "ACTIONS" ("ACT_ID")
      on delete restrict on update restrict;

alter table "PRIVILEDGES"
   add constraint "FK_PRIVILED_RSC_PRV_RESOURCE" foreign key ("DAT_ID")
      references "RESOURCE" ("DAT_ID")
      on delete restrict on update restrict;

alter table "RESOURCE"
   add constraint "FK_RESOURCE_RSC_DAT_BASIC_DA" foreign key ("DAT_ID")
      references "BASIC_DATA" ("DAT_ID")
      on delete restrict on update restrict;

alter table "TRANSLATIONS"
   add constraint "FK_TRANSLAT_LNG_TRL_LANGUAGE" foreign key ("LNG_ID")
      references "LANGUAGES" ("LNG_ID")
      on delete restrict on update restrict;

alter table "TRANSLATIONS"
   add constraint "FK_TRANSLAT_LPR_TRL_PROPERTI" foreign key ("LPR_ID")
      references "PROPERTIES" ("LPR_ID")
      on delete restrict on update restrict;

alter table "USERS"
   add constraint "FK_USERS_USR_CRY_COUNTRIE" foreign key ("CRY_ID")
      references "COUNTRIES" ("CRY_ID")
      on delete restrict on update restrict;

alter table "USERS"
   add constraint "FK_USERS_USR_LNG_LANGUAGE" foreign key ("LNG_ID")
      references "LANGUAGES" ("LNG_ID")
      on delete restrict on update restrict;

alter table "USERS"
   add constraint "FK_USERS_USR_PRS_BASIC_DA" foreign key ("DAT_ID")
      references "BASIC_DATA" ("DAT_ID")
      on delete restrict on update restrict;

alter table "WORKSPACE"
   add constraint "FK_WORKSPAC_WORKSPACE_BASIC_DA" foreign key ("DAT_ID")
      references "BASIC_DATA" ("DAT_ID")
      on delete restrict on update restrict;

