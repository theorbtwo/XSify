package ExtUtils::XSify;

use 5.10.0;
use strict;
use warnings;

use CLang;
use ExtUtils::XSify::TranslationUnit;

use Carp;
use autodie;
use Data::Dump::Streamer;
use Try::Tiny;
use charnames();

use Moose;

=head1 NAME

ExtUtils::XSify - Create XS wrappers for C-based libraries (using CLang)

=cut

has 'compile_me' => (is => 'ro', isa => 'Str');
has 'xs_filename' => (is => 'ro', isa => 'Str');
has 'output_dir' => (is => 'ro', isa => 'Str');
has 'xs_file' => (is => 'rw'); # isa => IO::Handle or something that can be used like one.
has 'includes' => (is => 'ro', isa => 'Str');
has 'base_module' => ( is => 'ro', isa => 'Str');
has 'ignore_macros' => ( is => 'ro', isa => 'ArrayRef', default => sub {[]});
has 'include_regex' => ( is => 'ro', isa => 'Str');
has 'ignore_all_macros' => (is => 'ro', isa => 'Bool');
has 'opencv_hack' => (is => 'ro', isa => 'Bool');
has 'typemap' => (is => 'rw', isa => 'ExtUtils::Typemaps');

has 'index',
  is => 'ro',
  lazy => 1,
  default => sub {
    # Do not exclude declarations from precompiled headers.
    # Do display diagnostics.
    return CLang::Index::createIndex(0, 1);
  };

has 'translation_unit',
  is => 'ro', isa => 'ExtUtils::XSify::TranslationUnit',
  required => 0,
  weak_ref => 0,
  lazy => 1,
  default => sub {
    my ($self) = @_;
    
    my $tu = $self->index->parseTranslationUnit($self->compile_me,
                                                undef, 0,
                                                undef, 0,
                                                # options -- |ed combination of CXTranslationUnit_Flags
                                                1  # CXTranslationUnit_DetailedPreprocessingRecord
                                               );

    return ExtUtils::XSify::TranslationUnit->new(translation_unit => $tu);
  };

sub xsify {
  my ($self) = @_;
  
  my %done;
  my @to_do = ($self->translation_unit);
  
  my $xs = {};
  my $pm = {};
  my $typemap = ExtUtils::Typemaps->new;

  try {
    while (@to_do) {
      my $to_do = shift @to_do;
      my $mark = $to_do->to_do_mark;
      
      next if $done{$mark};
      
      next if "$mark" ~~ [# Templates that seem to lose arguments?
                          'c:operations.hpp@115956@N@cv@F@format#&1$@N@cv@C@Mat#*1C#&1$@N@std@C@vector>#I#$@N@std@C@allocator>#I#',
                          'c:@N@cv@F@drawMatches#&1$@N@cv@C@Mat#&1$@N@std@C@vector>#$@N@cv@C@KeyPoint#$@N@std@C@allocator>#S4_#S0_#S2_#&1$@N@std@C@vector>#$@N@cv@S@DMatch#$@N@std@C@allocator>#S8_#&S1_#&1$@N@cv@C@Scalar_>#d#S11_#&1$@N@std@C@vector>#C#$@N@std@C@allocator>#C#I#',
                          'c:@N@cv@F@imwrite#&1$@N@std@C@basic_string>#C#$@N@std@S@char_traits>#C#$@N@std@C@allocator>#C#&1$@N@cv@C@_InputArray#&1$@N@std@C@vector>#I#$@N@std@C@allocator>#I#',
                          'c:@N@cv@F@imencode#&1$@N@std@C@basic_string>#C#$@N@std@S@char_traits>#C#$@N@std@C@allocator>#C#&1$@N@cv@C@_InputArray#&$@N@std@C@vector>#c#$@N@std@C@allocator>#c#&1$@N@std@C@vector>#I#$@N@std@C@allocator>#I#',
                          
                          # Nested templates
                          'c:@N@cv@F@drawMatches#&1$@N@cv@C@Mat#&1$@N@std@C@vector>#$@N@cv@C@KeyPoint#$@N@std@C@allocator>#S4_#S0_#S2_#&1$@N@std@C@vector>#$@N@std@C@vector>#$@N@cv@S@DMatch#$@N@std@C@allocator>#S9_#$@N@std@C@allocator>#S8_#&S1_#&1$@N@cv@C@Scalar_>#d#S13_#&1$@N@std@C@vector>#$@N@std@C@vector>#C#$@N@std@C@allocator>#C#$@N@std@C@allocator>#S17_#I#',
                          'c:@N@cv@F@computeRecallPrecisionCurve#&1$@N@std@C@vector>#$@N@std@C@vector>#$@N@cv@S@DMatch#$@N@std@C@allocator>#S3_#$@N@std@C@allocator>#S2_#&1$@N@std@C@vector>#$@N@std@C@vector>#c#$@N@std@C@allocator>#c#$@N@std@C@allocator>#S8_#&$@N@std@C@vector>#$@N@cv@C@Point_>#f#$@N@std@C@allocator>#S13_#',
                          'c:@N@cv@F@evaluateGenericDescriptorMatcher#&1$@N@cv@C@Mat#S0_#S0_#&$@N@std@C@vector>#$@N@cv@C@KeyPoint#$@N@std@C@allocator>#S4_#S2_#*$@N@std@C@vector>#$@N@std@C@vector>#$@N@cv@S@DMatch#$@N@std@C@allocator>#S9_#$@N@std@C@allocator>#S8_#*$@N@std@C@vector>#$@N@std@C@vector>#c#$@N@std@C@allocator>#c#$@N@std@C@allocator>#S14_#&$@N@std@C@vector>#$@N@cv@C@Point_>#f#$@N@std@C@allocator>#S19_#&1$@N@cv@C@Ptr>#$@N@cv@C@GenericDescriptorMatcher#',
                          'c:@N@cv@F@chamerMatching#&$@N@cv@C@Mat#S0_#&$@N@std@C@vector>#$@N@std@C@vector>#$@N@cv@C@Point_>#I#$@N@std@C@allocator>#S5_#$@N@std@C@allocator>#S4_#&$@N@std@C@vector>#f#$@N@std@C@allocator>#f#d#I#d#I#I#I#d#d#d#d#',
                          
                          # Function pointers
                          'c:@N@cv@F@startLoop#*FII**C#I#S2_#'
                         ];
      
      print "Working on $mark\n";
      
      my @more = $to_do->more_to_do;
      
      if (grep {not defined $_} @more) {
        die "Got an undef for more to do, mark was $mark, stringify $to_do";
      }
      
      unshift @to_do, @more;
      
      
      
      $to_do->make_xs($xs, $pm, $typemap);
      
      $done{$mark}++;
      
      print "Done: $mark\n";
      
      if ((keys(%done) % 10) == 0) {
        Dump({xs => $xs,
              pm => $pm,
              typemap => $typemap});
      }
    }
  } catch {
    print "Died with $_";
  };

  open my $xs_file, ">", 'generated/opencv/opencv.xs';
  for my $module (keys %$xs) {
    print $xs_file "MODULE = $module   PACKAGE = $module\n\n";
    for my $func (@{$xs->{$module}}) {
      print $xs_file "$func\n";
    }
  }
  print $xs_file "MODULE = OpenCV  PACKAGE = OpenCV\n\n";

  $typemap->write(file => 'generated/opencv/typemap');
}


'Thaaaaaaaaaaaaaaats all, folks!';
