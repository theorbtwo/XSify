package ExtUtils::XSify::Type;
use 5.10.0;
use warnings;
use strict;
use Data::Dump::Streamer;
use Carp;

# no moose, this is just a factory.

sub new {
  my ($self, %args) = @_;
  my $type = $args{type};
  my $location = $args{location};
  
  $location ||= "FIXME: ".join(", ", caller);

  die "Cannot ExtUtils::XSify::Type without a type"
    if !$type;

  if (!$args{parent_cursor}) {
    confess "Type->new didn't get passed a parent_cursor";
  }

  my $type_kind = $type->getTypeKind;
  my $decl_kind = $type->getTypeDeclaration->getCursorKind;

  my $class;

  state $basic_type = {
                       3 => 'bool',
                       # When char happens to be unsigned.
                       4 => 'char',
                       9 => 'unsigned int',
                       13 => 'char', # when char happens to be signed.
                       17 => 'int',
                       15 => 'wchar',
                       16 => 'short',
                       18 => 'long',
                       19 => 'long long',
                       21 => 'float',
                       22 => 'double',
                       23 => 'long double',
                      };

  if ($basic_type->{$type_kind}) {
    my $basic_type_name = $basic_type->{$type_kind};

    my $class = "ExtUtils::XSify::Type::Basic::$basic_type_name";
    $class =~ s/ /_/g;
    eval "use $class; 1" or die $@;

    return $class->new;
  }

  state $explicit_type = {2 => 'Struct',
                          4 => 'Class',
                          5 => 'Enum',
                          20 => 'Typedef',
                         };

  if ($explicit_type->{$decl_kind}) {
    my $explicit_type_name = $explicit_type->{$decl_kind};

    my $class = "ExtUtils::XSify::Type::Explicit::$explicit_type_name";
    eval "use $class; 1" or die $@;

    return $class->new(cursor => $type->getTypeDeclaration);
  }

  given ($type_kind) {
    when (1) {
      # "Unhandled"
      #  libclang isn't good enough to do anything useful here for us, so we
      #  need to do it by ourselves.
      
      return $self->new_for_strangeness(%args);
    }
    
    when (2) {
      # void
      return undef;
    }


    when (100) {
      $class = 'ExtUtils::XSify::Type::Complex';
    }

    when (101) {
      $class = 'ExtUtils::XSify::Type::Pointer';
    }

    when (103) {
      $class = 'ExtUtils::XSify::Type::LValueReference';
    }

    default {
      die "Do not know how to create an ExtUtils::XSify::Type for a type of kind $type_kind, decl kind $decl_kind";
    }
  }

  eval "use $class; 1" or die $@;
  
  print "Pasing off to $class\n";

  return $class->new(type => $type,
                     location => $location,
                     parent_cursor => $args{parent_cursor});
}


# There are at least two different sorts of strangeness that can end up here:
# 1: templates.
#    void foo(const vector<int>& fromTo);
# 2: namespaced types?
#    const std::string& name

sub new_for_strangeness {
  # calls new_for_templates, new_for_namespaced, ..., until one succeeds
  my $self = shift;

  my $type;
  foreach my $handler (qw/new_for_templates new_for_namespaced/) {
    last if($type = $self->$handler(@_));
  }
  
  if (!$type) {
    die "What new devilry is this?";
  }

  return $type;
}

sub new_for_namespaced {
  my ($self, %args) = @_;
  my $location = $args{location};
  my $parent_cursor = $args{parent_cursor};

  Dump \%args;

  ExtUtils::XSify::FunctionDecl::dump_visit_tree($args{parent_cursor});

  # namespaced types?
  #    template<> bool CommandLineParser::get<bool>(const std::string& name, bool space_delete);
  #    ... but we actually get here for std::string name?


  my ($ns_type);

  my $solved = 0;
  $parent_cursor->visitChildren
    (sub {
       my ($child_cursor) = @_;

       my $kind = $child_cursor->getCursorKind;
       if ($kind == 46) {
         # the 'std::' (namespace) part, ignore this as the following typeref should know what ns its in anyway
       } elsif ($kind == 43 && !$ns_type) {
         # The actual namespaced type should be 43, TypeRef.
         # This is the actual type, eg 'string'
         my $loc = $child_cursor->getCursorLocation;
         my $presumed_filename = $loc->getPresumedLocationFilename;
         my $presumed_line = $loc->getPresumedLocationLine;

         my $location = "$presumed_filename:$presumed_line";

         $ns_type =  ExtUtils::XSify::Type
           ->new(type => $child_cursor->getCursorReferenced->getCursorType,
                 location => $location,
                 parent_cursor => $child_cursor
                );
         $solved = 1;

         # We used to require that a namespaced name be zero or more 46es and exactly one 43,
         # but this fails when the namespaced name is the return type of a function/method, see
         # /usr/include/opencv2/core/core.hpp:4323
         return 0;
       } else {
         warn "This doesn't seem to be a namespaced name?";
         $solved = 0;
         return 0;
       }

       return 1;
     });

  return undef if(!$solved);

  return $ns_type;
}

# pointee of /usr/include/opencv2/core/operations.hpp:3516 argument named params
# static inline Formatted format(const Mat& mtx, const char* fmt, const vector<int>& params=vector<int>())
#10 (ParmDecl) [sp: 'params']
# 45 (TemplateRef) [sp: 'vector']
# 100 (unexposed)
#  100 (unexposed)
#   100 (unexposed)
#    100 (unexposed)
#     103 (CallExpr) [sp: 'vector']
#      45 (TemplateRef) [sp: 'vector']
#Child 1 of a 1 is a cursor kind 100 (template takes 1 parameters) at /mnt/shared/projects/c/perl-clang/blib/lib/ExtUtils/XSify/Type.pm line 247.

# pointee of /usr/include/opencv2/features2d/features2d.hpp:2966 argument named matchesMask
# CV_EXPORTS void drawMatches( const Mat& img1, const vector<KeyPoint>& keypoints1,
#                             const Mat& img2, const vector<KeyPoint>& keypoints2,
#                             const vector<DMatch>& matches1to2, Mat& outImg,
#                             const Scalar& matchColor=Scalar::all(-1), const Scalar& singlePointColor=Scalar::all(-1),
#                             const vector<char>& matchesMask=vector<char>(), int flags=DrawMatchesFlags::DEFAULT );
# const vector<char>& matchesMask=vector<char>()
# 10 [sp: 'matchesMask']
# 45 [sp: 'vector']
# 100
#  100
#   100
#    100
#     103 [sp: 'vector']
#      45 [sp: 'vector']


## Function pointers:

# pointee of /usr/include/opencv2/highgui/highgui.hpp:83 argument named pt2Func
# 10 [sp: 'pt2Func']
#  10 [sp: 'argc']
#  10 [sp: 'argv']
# CV_EXPORTS  int startLoop(int (*pt2Func)(int argc, char *argv[]), int argc, char* argv[]);



sub new_for_templates {
  my ($self, %args) = @_;
  my $location = $args{location};
  my $parent_cursor = $args{parent_cursor};

  Dump \%args;

  ExtUtils::XSify::FunctionDecl::dump_visit_tree($args{parent_cursor});

  # Nested templates

  # pointee of /usr/include/opencv2/features2d/features2d.hpp:2972 argument named matches1to2
  # const vector<vector<DMatch> >& matches1to2
  # 10 [sp: 'matches1to2']
  #  45 [sp: 'vector']
  #  45 [sp: 'vector']
  #  43 [sp: 'struct cv::DMatch']

  # Namespaced templates

  # pointee of /usr/include/opencv2/objdetect/objdetect.hpp:276 argument named rejectLevels
  # std::vector<int>& rejectLevels
  # 10 (ParmDecl) [sp: 'rejectLevels']
  #  46 (NamespaceRef) [sp: 'std']
  #  45 (TemplateRef) [sp: 'vector']

  my $n=0;
  my ($template, @parameters);

  my $solved = 1;
  $parent_cursor->visitChildren
    (sub {
       my ($child_cursor) = @_;

       my $kind = $child_cursor->getCursorKind;
       if ($kind == 46) {
         # Ignore these.  Don't even increase $n.
         return 1;
       } elsif ($kind == 45 and $n == 0) {
         # First child of the parent cursor should be a templateref.
         $template = ExtUtils::XSify::Type::Template->new(template_ref => $child_cursor);

       } elsif ($kind == 43 and $n > 0 and $n <= $template->num_parameters) {
         # The rest of the children should be 43, TypeRef.
         # (This would be less delicate if we knew how many template parameters to expect?)
         my $loc = $child_cursor->getCursorLocation;
         my $presumed_filename = $loc->getPresumedLocationFilename;
         my $presumed_line = $loc->getPresumedLocationLine;

         my $location = "$presumed_filename:$presumed_line";

         push @parameters, ExtUtils::XSify::Type
           ->new(type => $child_cursor->getCursorReferenced->getCursorType,
                 location => $location,
                 parent_cursor => $child_cursor
                );

       } elsif ($template and $n > $template->num_parameters) {
         # We've found a CompoundStmt, the body of the function.  Stop.
         return 0;

       } elsif ($template) {
         my $tp = $template->num_parameters;
         die "Child $n of a 1 is a cursor kind $kind (template takes $tp parameters)";
       } else {
         warn "Child $n of a 1 is a cursor kind $kind, and we haven't seen a template";
         $solved = 0;
         return 0;
       }

       $n++;
       return 1;
     });

  return undef if(!$solved);

  return $template->instance(\@parameters);
}

'wazzat?';
