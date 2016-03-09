use ExtUtils::MakeMaker;
#
#require 5.6;

WriteMakefile(
  'NAME'         => 'NodeGitProj',  #  module name (Mod::Pack)
  #'DISTNAME' => '', # Explicit dist filename
  'VERSION_FROM' => 'NodeGitProj.pm', # finds $VERSION
  'ABSTRACT'     => 'Manage the Deployment lifecycle of Git Stored Node.js App.',
  #ABSTRACT_FROM
  'AUTHOR'       => 'Olli Hollmen',
  # Class name => ver
  'PREREQ_PM'    => {
    'Data::Dumper' => 0,
    'JSON' => 0, # libjson-perl
    'Mail::Sendmail' => 0, # libmail-sendmail-perl
    'Date::ISO8601' => 0, # libdate-iso8601-perl
  },
  # Ref to executables to be copied to INST_SCRIPT directory
  'EXE_FILES' => ['bin/nodegit'],
  # Mapping of XS to C files
  #'XS' => {'NodeGitProj.xs' => 'NodeGitProj.c'},
  #'XSOPT' => '-extern',
  #'TYPEMAPS' => ['','']
);
