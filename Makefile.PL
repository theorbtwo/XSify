#!/bin/env perl
use warnings;
use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
#              OPTIMIZE => '-g4 -O0',
#              CC => 'clang',
              NAME => 'CLang',
              LIBS => ['-lclang'],
              VERSION => '0.001',
              BUILD_REQUIRES => {
                                 'ExtUtils::MakeMaker' => 0,
                                 'ExtUtils::ParseXS' => '3.11',
                                },
             );
