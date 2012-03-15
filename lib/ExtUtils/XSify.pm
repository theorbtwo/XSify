package ExtUtils::XSify;

use 5.10.0;
use strict;
use warnings;

use CLang;

use Carp;
use autodie;
use Data::Dump::Streamer;
use charnames();

use Moose;

=head1 NAME

ExtUtils::XSify - Create XS wrappers for C-based libraries (using CLang)

=cut

has 'xs_filename' => (is => 'ro', isa => 'Str');
has 'output_dir' => (is => 'ro', isa => 'Str');
has 'xs_file' => (is => 'rw'); # isa => IO::Handle or something that can be used like one.
has 'includes' => (is => 'ro', isa => 'Str');
has 'base_module' => ( is => 'ro', isa => 'Str');
has 'compile_me' => (is => 'ro', isa => 'Str');
has 'ignore_macros' => ( is => 'ro', isa => 'ArrayRef', default => sub {[]});
has 'include_regex' => ( is => 'ro', isa => 'Str');
has 'ignore_all_macros' => (is => 'ro', isa => 'Bool');
has 'opencv_hack' => (is => 'ro', isa => 'Bool');
has 'typemap' => (is => 'rw', isa => 'ExtUtils::Typemaps');

sub xsify {
    my ($self) = @_;

    open my $xs_file, ">", $self->output_dir."/".$self->xs_filename;
    $self->xs_file($xs_file);

    my $includes = $self->includes;
    my $base = $self->base_module;

    $xs_file->print(<<END);
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

$includes

MODULE = $base  PACKAGE = $base

PROTOTYPES: DISABLE

END

    my $index = CLang::Index::createIndex(0, 1);

    my $tu = $index->parseTranslationUnit(#"/usr/include/clang-c/Index.h",
                                          $self->compile_me,
                                          undef, 0,
                                          undef, 0,
                                          # options -- |ed combination of CXTranslationUnit_Flags
                                          1  # CXTranslationUnit_DetailedPreprocessingRecord
        );
    my $tu_cursor = $tu->getTranslationUnitCursor();



    my @todo = (
        {cursor => $tu_cursor}
        );

    $self->typemap(ExtUtils::Typemaps->new());

    my $xs = '';

    while (@todo) {
        my ($todo_item) = shift @todo;

        if (exists $todo_item->{cursor}) {
            state $done = {};
            if ($done->{$todo_item->{cursor}->getCursorUSR}++) {
              print "Skipping, already had this cursor-flavoured todo item (why=$todo_item->{why})\n";
              next;
            }

            my $cursor = $todo_item->{cursor};
            my $kind = $cursor->getCursorKind;

            given ($kind) {
                when ([2, 3, 4]) {
                    # 2: struct
                    # 3: union
                    # 4: class
                    $self->handle_record($todo_item, \@todo);
                }

                when (5) {
                    # enum
                    $self->handle_enum($todo_item, \@todo);
                }

                when (6) {
                    # field
                    $self->handle_field($todo_item, \@todo);
                }

                when (7) {
                    # enum constant
                    $self->handle_enum_constant($todo_item, \@todo);
                  }
                
                when ([8,  # function
                       21, # C++ class method
                       24, # constructor
                       25, # destructor
                       26, # conversion function
                      ]) {
                  $self->handle_function($todo_item, \@todo);
                  }
                
                when ([ 9, # VarDecl
                        20, # TypedefDecl
                        30, # FunctionTemplate
                        31, # ClassTemplate
                      ]) {
                  # Oh, hell, really can't be arsed right now.
                }

                when (300) {
                  # translation unit
                  $self->handle_translation_unit($todo_item, \@todo);
                }

                when (501) {
                  $self->handle_macro_definition($todo_item, \@todo);
                }

                default {
                  die "In todo-loop, don't know what to do with cursor-flavored todo item kind $kind";
                }
            }
        } elsif (exists $todo_item->{type}) {
            $self->handle_type($todo_item, \@todo);
        } else {
            die "In todo-loop, don't know what to do with this";
        }
    }

    $self->xs_file->print(<<END);

MODULE = $base  PACKAGE = $base

END

    $self->typemap->write(file => $self->output_dir."/typemap") or die;

}

sub handle_macro_definition {
  my ($self, $todo_item, $todo) = @_;

  #say "In handle_macro_definition";
  #Dump $todo_item;

  my $cursor = $todo_item->{cursor};
  my $spelling = "".$cursor->getCursorSpelling;
  #print "Macro spelling: $spelling\n";

  if ($self->ignore_all_macros) {
    return;
  }

  if ($spelling ~~ $self->ignore_macros) {
    return;
  }

  $self->xs_file->print(<<END)

SV *
__macro_val_$spelling()
 CODE:
  typeof($spelling) val = $spelling;

  if (__builtin_types_compatible_p(typeof(val), UV)) {
    RETVAL = newSVuv(val);
  } else if (__builtin_types_compatible_p(typeof(val), IV)) {
    RETVAL = newSViv(val);
  } else if (__builtin_types_compatible_p(typeof(val), int)) {
    RETVAL = newSViv(val);
  } else if (__builtin_types_compatible_p(typeof(val), void *) &&
             (void*)val == NULL) {
    RETVAL = newSV(0);
  } else {
    croak("Don't know how to transform the value of macro ${spelling} into an SV");
  }

 OUTPUT:
  RETVAL

END
}

sub handle_type {
  my ($self, $todo_item, $todo) = @_;
  
  my $type = $todo_item->{type};
  my $c_name = $self->type_to_c_name($type);
  my $perl_name = $self->type_to_perl_name($type);
  
  my $location = $type->getTypeDeclaration->getCursorLocation;
  my $filename = $location->getPresumedLocationFilename;
  my $line = $location->getPresumedLocationLine;
  
  die "Trying to handle a type that I can't find the c name of from $filename line $line"
    if not defined $c_name;
  
  state $done;
  return if $done->{$c_name}++;
  
  # Types that are handled just fine by the default typemap.
  return if "$c_name" ~~ [
                          # integer types
                          'unsigned int', 'int',
                          'unsigned long', 'long',
                          'size_t', 'ssize_t',
                          # pointer types
                          'char*'
                         ];

  print "Trying to handle_type for $c_name\n";

  if ($type->getTypeDeclaration and
      $type->getTypeDeclaration->getCursorKind !=71, # NoDeclFound
     ) {
    push @$todo, {
                  cursor => $type->getTypeDeclaration,
                  why => "type used by ($todo_item->{why})",
                 };
  } elsif ($type->getPointeeType) {
    push @$todo, {
                  cursor => $type->getPointeeType->getTypeDeclaration,
                  why => "pointee of a type used by ($todo_item->{why})",
                 };
  }

  my $kind_raw = $type->getTypeKind;
  state $my_kind_map = {
                        # "Unexposed"
                        1 => 'magic_unexposed',
                        2 => 'void',
                        3 => 'UV',
                        5 => 'UV',
                        8 => 'UV',
                        9 => 'UV',
                        11 => 'UV',
                        14 => 'IV',
                        13 => 'IV',
                        16 => 'IV',
                        17 => 'IV',
                        18 => 'IV',
                        19 => 'IV',
                        21 => 'NV',
                        22 => 'NV',
                        101 => 'pointer',
                        # &-reference.
                        103 => 'nonpointer',
                        #103 => 'pointer',
                        # Struct
                        105 => 'nonpointer',
                        # enum
                        106 => 'nonpointer',
                        107 => 'typedef',
                        # ConstantArray (array of constant length).
                        112 => 'nonpointer',
                       };
  if (not exists $my_kind_map->{$kind_raw}) {
    confess "Don't know how to handle type of type kind $kind_raw for $c_name from $filename line $line (via $todo_item->{why})";
  }
  my $kind = $my_kind_map->{$kind_raw};
  
  if ($kind eq 'magic_unexposed') {
    my $declaration = $type->getTypeDeclaration();
    if (!$declaration) {
      die "Unexposed type with no declaration";
    }
    my $decl_kind = $declaration->getCursorKind;
    given ($decl_kind) {
      when (2) {
        $kind = 'nonpointer';
      }
      when (4) {
        # C++ class
        $kind = 'nonpointer';
      }
      when (5) {
        $kind = 'enum';
      }
      when (31) {
        # This isn't really a type, it's a reference to a template parameter.
        return;
      }
      default {
        my $filename = $declaration->getCursorLocation->getPresumedLocationFilename;
        my $line = $declaration->getCursorLocation->getPresumedLocationLine;

        die "Unexposed type with declaration kind $decl_kind, declared at $filename line $line";
      }
    }
  }
  
  if ($kind eq 'typedef') {
    #if (type_to_c_name($type->getCanonicalType)) {
    #  my $xs_name = type_to_xs_name($type->getCanonicalType);
    #  $typemap->add_typemap(ctype => $c_name,
    #                        xstype => $xs_name);
    #  return;
    #} else {
      $kind = 'nonpointer';
    #}
  }
  
  given ($kind) {
    when ([qw<NV IV UV>]) {
      $self->typemap->add_typemap(ctype => $c_name,
                                  xstype => "T_".$kind,
                                 );
    }

    when ('enum') {
      push @$todo, {cursor => $type->getTypeDeclaration,
                    why => "from used type (enum)",
                   };

      my $xs_name = $self->type_to_xs_name($type);
      $self->typemap->add_typemap(ctype => $c_name, xstype => $xs_name);
      $self->typemap->add_outputmap(xstype => $xs_name,
                                    code => <<END);
	    sv_setref_iv( \$arg, "$perl_name", \$var );
END
      $self->typemap->add_inputmap(xstype => $xs_name,
                                   code => <<END);
    if( sv_isobject(\$arg) && (SvTYPE(SvRV(\$arg)) == SVt_PVMG) ) {
      /* FIXME: Should probably check if isa $perl_name */
      /* FIXME: Should we allow passing in an IV/UV? */
      \$var = (\$type)SvIV(SvRV( \$arg ));
    } else {
      warn( \\"\${Package}::\$func_name() -- \$var is not a blessed SV reference\\" );
      XSRETURN_UNDEF;
    }

END
    }

    when ('nonpointer') {
      my $xs_name = $self->type_to_xs_name($type);
      $self->typemap->add_typemap(ctype => $c_name,
                                  xstype => $xs_name);
      $self->typemap->add_outputmap(xstype => $xs_name,
                                    code => <<END);
	    sv_setref_pvn( \$arg, "$perl_name", (const char* const)&\$var, sizeof(\$var) );
END
      $self->typemap->add_inputmap(xstype => $xs_name,
                                   code => <<END);
    if( sv_isobject(\$arg) && (SvTYPE(SvRV(\$arg)) == SVt_PVMG) ) {
      /* FIXME: Should probably check if isa $perl_name */
      Copy(SvPV_nolen(SvRV(\$arg)),
           &\$var,
           1, $c_name
          );
    } else {
      warn( \\"\${Package}::\$func_name() -- \$var is not a blessed SV reference\\" );
      XSRETURN_UNDEF;
    }

END

#      $self->xs_file->print(<<END);
#
#
#MODULE = $perl_name  PACKAGE = $perl_name
#
#$c_name
#__allocate(char *self)
#  OUTPUT:
#    RETVAL
#
#END
    }
    
    when ('pointer') {
      my $xs_name = $self->type_to_xs_name($type);
      $self->typemap->add_typemap(ctype => $c_name,
                                  xstype => $xs_name);
      $self->typemap->add_outputmap(xstype => $xs_name,
                                    code => <<END);
	    sv_setref_iv( \$arg, "$perl_name", (int)\$var );
END
      $self->typemap->add_inputmap(xstype => $xs_name,
                                   code => <<END);
    if( sv_isobject(\$arg) && sv_does(\$arg, \\"$perl_name\\") ) {
      \$var = (\$type)SvIV((SV*)SvRV( \$arg ));
    } else if ( !SvOK(\$arg) ) {
      \$var = NULL;
    } else {
      warn( \\"\${Package}::\$func_name() -- \$var is not a $perl_name\\" );
      XSRETURN_UNDEF;
    }

END

      my $make_dereference;
      my $make_enreference;
      my $make_allocate;

      # Right.  Now we need to figure out if we can actually handle the type that this points at.
      my $canon_pointee = $type->getPointeeType->getCanonicalType;
      my $canon_pointee_type_kind = $canon_pointee->getTypeKind;
      my $canon_pointee_decl_kind = $canon_pointee->getTypeDeclaration->getCursorKind;
      my $canon_pointee_definition = $canon_pointee->getTypeDeclaration->getCursorDefinition;
      my $canon_pointee_definition_kind = $canon_pointee_definition->getCursorKind;
      #print "Canon pointee type kind: $canon_pointee_type_kind\n";
      print "Canon pointee decl kind: $canon_pointee_decl_kind\n";
      #print "Canon pointee defintion: $canon_pointee_definition\n";
      #print "Canon pointee defintion: $$canon_pointee_definition\n";
      print "Canon pointee definition kind: $canon_pointee_definition_kind\n";

      if ($canon_pointee_type_kind == 2) {
        # void*
      } elsif ($canon_pointee_type_kind ~~ [5, 13, 17]) {
        # A pointer to a unsigned char
        # A pointer to a char (signed)
        # A pointer to an int
        print "Pointer to a simple thing, make en/dereferencers?\n";
      } elsif ($canon_pointee_type_kind == 101) {
        # A pointer to a pointer.  These don't need an explicit declaration of the pointee type, they should always be safe:
        # libusb_context**

        push @$todo, {type => $type->getPointeeType,
                      why => "pointee type from (".$todo_item->{why}.")"
                     };
        
        $make_dereference = 1;
        $make_enreference = 1;
        $make_allocate = 1;
      } elsif ($canon_pointee_type_kind == 105) {
        # 105: A pointer to a record.
        # These need an explicit definition of the pointee type -- we can't make a dereferencer to a struct type that has only a forward declaration, but not real definition.
        if ($canon_pointee_definition_kind == 2) {
          # CXCursor_StructDecl
          print "Pointer to a defined record, make en/dereferencers\n";
          $make_dereference=1;
          $make_enreference=1;
          $make_allocate=1;
        } elsif ($canon_pointee_definition_kind == 70) {
          # CXCursor_InvalidFile (or CXCursor_FirstInvalid)
          # We can't dereference these, but we can allocate and enreference them.
          $make_allocate = 1;
          $make_enreference = 1;
          print "Non-dereferenceable perl name $perl_name\n";
        } else {
          die "Pointer to a record, cpdk = $canon_pointee_definition_kind";
        }
      } else {
        die "Not sure if $c_name can have a dereferencer -- canon_pointee_type_kind == $canon_pointee_type_kind";
      }

      if ($make_dereference and !$type->getPointeeType->isConstQualifiedType
         ) {
        # isConstQualifiedType should hopefully go away...
        my $deref_c_name = $self->type_to_c_name($type->getPointeeType);
        push @$todo, {type => $type->getPointeeType,
                      why => "pointee type for (". $todo_item->{why} .")"};

        $self->xs_file->print(<<END);

MODULE = $perl_name  PACKAGE = $perl_name

$deref_c_name
__dereference($c_name pointer)
  CODE:
    RETVAL = *pointer;
  OUTPUT:
    RETVAL

END
      }

      if ($make_enreference) {
        my $deref_perl_name = $self->type_to_perl_name($type->getPointeeType);
        my $deref_c_name    = $self->type_to_c_name($type->getPointeeType);


        $self->xs_file->print(<<END);

MODULE = $deref_perl_name  PACKAGE = $deref_perl_name

$c_name
__enreference(SV *base)
  CODE:
    /* FIXME: Check that base is a reasonable type of SV first. */
    SV *inside = SvRV(base);
    RETVAL = ($c_name)&(SvIVX(inside));
  OUTPUT:
    RETVAL

END
      }

      if ($make_allocate) {
        $self->xs_file->print(<<END);

MODULE = $perl_name  PACKAGE = $perl_name

$c_name
__allocate(char *self)
  CODE:
    RETVAL = NULL;
  OUTPUT:
    RETVAL

END
      }

    }


    default {
      die "handle_type for c_name=$c_name, perl_name=$perl_name, kind = $kind ($kind_raw)";
    }
  }
}

sub type_to_xs_name {
  my ($self, $type) = @_;
  die if @_ < 2;

  my $xsname = $self->type_to_c_name($type);
  $xsname =~ s/\*/_Star/g;
  $xsname =~ s/\&/_Amp/g;
  $xsname =~ s/ /_/g;
  $xsname =~ s/::/_coloncolon_/g;
  $xsname = "XS_$xsname";

  return $xsname;
}

sub handle_enum_constant {
    my ($self, $todo_item, $todo) = @_;

    my $cursor = $todo_item->{cursor};
    my $perl_class = $self->type_to_perl_name($todo_item->{parent_enum}->getCursorType);
    if (not defined $perl_class) {
      return;
    }
    my $c_name = $cursor->getCursorSpelling;

    # FIXME: the XS function should probably have the same return type as the type that underlays
    # the enum, which IIRC, could technically be any type?  (Any inegral type?)

    $self->xs_file->print(<<END);

MODULE = $perl_class  PACKAGE = $perl_class

int
__value_$c_name(void)
 CODE:
  RETVAL = $c_name;
 OUTPUT:
  RETVAL

END
}

sub handle_enum {
    my ($self, $todo_item, $todo) = @_;

    return if $todo_item->{access} and $todo_item->{access} eq 'private';

    my $cursor = $todo_item->{cursor};

    $cursor->visitChildren(sub {
	my ($elem_cursor) = @_;
	
	given ($elem_cursor->getCursorKind) {
	    when (7) {
		push @$todo, {
		    cursor => $elem_cursor,
		    parent_enum => $cursor,
                    why => 'enum element',
		};
	    }
	    default {
		my $spelling = $elem_cursor->getCursorSpelling;
		my $filename = $elem_cursor->getCursorLocation->getPresumedLocationFilename;
		my $line = $elem_cursor->getCursorLocation->getPresumedLocationLine;
		die "Enum child of kind $_, spelling $spelling, from $filename at line $line";
	    }
	}
      });
}

sub handle_field {
    my ($self, $todo_item, $todo) = @_;

    return if $todo_item->{access} && $todo_item->{access} eq 'private';

    my $cursor = $todo_item->{cursor};

    #print STDERR "handle_field, parent_class is: ", $todo_item->{parent_class}, "\n";
    my $class_perl = $self->type_to_perl_name($todo_item->{parent_class});
    my $class_c    = $self->type_to_c_name($todo_item->{parent_class});
    my $field_class_c = $self->type_to_c_name($cursor->getCursorType);
    my $field_name = $cursor->getCursorSpelling;

    if (not $field_class_c) {
      warn "Failed to get type for $field_name of $class_c";
      return;
    }

    push @$todo, {
                  why => "type of field $field_name of $class_c",
                  type => $cursor->getCursorType,
                 };

    $self->xs_file->print(<<END);

MODULE = $class_perl  PACKAGE = $class_perl

$field_class_c
__get_$field_name($class_c record)
 CODE:
  RETVAL = record.$field_name;
 OUTPUT:
  RETVAL


void
__set_$field_name($class_c record, $field_class_c new_val)
 CODE:
  record.$field_name = new_val;

END
}

sub handle_function {
  my ($self, $todo_item, $todo) = @_;
  
  my $cursor = $todo_item->{cursor};
  
  my $flavour;
  given ($cursor->getCursorKind) {
    when (8) {
      $flavour = 'function';
    }
    when (21) {
      $flavour = 'method';
    }
    when (24) {
      $flavour = 'constructor';
    }
    when (25) {
      $flavour = 'destructor';
    }
    when (26) {
      $flavour = 'conversion';
    }
    default {
      say "Don't know what sort of function-like-thing has cursor kind $_";
      die;
    }
  }
  
  my $namespaced_name = $self->namespaced_name($cursor);
  my $spelling = $cursor->getCursorSpelling;
  my $filename = $cursor->getCursorLocation->getPresumedLocationFilename;
  my $line = $cursor->getCursorLocation->getPresumedLocationLine;
  
  if ($spelling =~ m/^operator/) {
    
    if ($spelling =~ m/^operator (\w+)$/) {
      $spelling = "__convert_to_".$1;
    } elsif ($spelling =~ m/^operator /) {
      warn "Ignoring strange operator $spelling";
      return;
    } elsif ($spelling =~ m/^operator([-()*\[\]=!&+><\/|^~]+)$/) {
      $spelling = $1;
      $spelling = join '_', map {charnames::viacode(ord $_)} split //, $1;
      $spelling =~ s/ /_/g;
      $spelling =~ s/-//g;
      $spelling = '__operator_'.$spelling;
    } else {
      die "Er, strange operator spelling of a function-like ($flavour): $spelling";
    }
    
  }
  
  #print "working on $flavour $namespaced_name from $filename line $line\n";
  
  my $dead;
  my $return_type;
  given ($flavour) {
    when ('constructor') {
      $return_type = $todo_item->{parent_class} || $cursor->getCursorSemanticParent->getCursorType;
    }
    when (['function', 'method', 'conversion']) {
      $return_type = $cursor->getCursorResultType;
    }
    when ('destructor') {
      # Will return void, which is what we wanted.
      $return_type = $cursor->getCursorResultType;
      
      $spelling = 'DESTROY';
    }
    default {
      die "Getting return type for function-like flavour $flavour";
    }
  }
  my $return_type_c = $self->type_to_c_name($return_type) unless $dead;
  if (!$return_type_c) {
    $dead = "can't map return type to a c name";
  }
  
  push @$todo, {type => $return_type, why => "return type of $namespaced_name, $filename line $line"}
    unless ($dead or
            $return_type_c.'' eq 'void');
  
  my $arguments = [];
  
  my $anon_count = 0;
  
  $cursor->visitChildren(sub {
                           return 0 if $dead;
                           
                           my ($arg_cursor) = @_;
                           
                           my $filename = $arg_cursor->getCursorLocation->getPresumedLocationFilename;
                           my $line = $arg_cursor->getCursorLocation->getPresumedLocationLine;
                           
                           given ($arg_cursor->getCursorKind) {
                             when (10) {
                               # ParmDecl
                               my $name = $arg_cursor->getCursorSpelling || ("anon_".$anon_count++);
                               
                               my $c_type = $self->type_to_c_name($arg_cursor->getCursorType);
                               if (not defined $c_type) {
                                 $dead = "cannot map type for argument $name to c type";
                               }
                               
                               push @$todo, {type => $arg_cursor->getCursorType, why => "argument type - $namespaced_name(..., $name, ...) from $filename line $line"} unless $dead;
                               
                               push @$arguments, [$c_type, $name];
                               
                               return 1;
                             }
                             
                             when (43) {
                               # TypeRef?
                               
                               # inline const DiagnosticBuilder &operator<<(const DiagnosticBuilder &DB, StringRef S)
                               # --> class clang::DiagnosticBuilder
                               
                               #say "TypeRef as a sub-cursor of a function-like ($flavour) at $filename line $line";
                               #say "spelling: ", $arg_cursor->getCursorSpelling;
                               return 1;
                             }
                             
                             when (202) {
                               # Compound statement -- the body of a function.  We don't care
                               return 1;
                             }
                             
                             when (45) {
                               # TemplateRef
                               $dead = 'templatey bit';
                               return 0;
                             }
                             
                             when (46) {
                               # namespace gubbins?
                               return 1;
                             }
                             
                             when ([ 47, # MemberRef
                                     106, # IntegerLiteral
                                     100, # UnexposedExpr
                                     101, # DeclRefExpr
                                     103, # CallExpr
                                     107, # floating-point literal
                                     130, # Bool const
                                     112, # unary operator
                                     116, # ?:
                                     117, # C-style cast expression
                                     127, # C++ const_cast<>
                                     134, # new Object(foo)
                                     114, # binary operator
                                   ]) {
                               # All these appear to be designated initializer syntax -- wish this interface
                               # was slightly higher-level, so they'd all be children of one parent.
                               return 1;
                             }
                             
                             default {
                               my $filename = $arg_cursor->getCursorLocation->getPresumedLocationFilename;
                               my $line = $arg_cursor->getCursorLocation->getPresumedLocationLine;
                               die "Don't know what to do with child of a function-like of kind $_ at $filename line $line";
                             }
                           }
                           
                         });
  
  if ($dead) {
    warn "Cannot output xs for function-like $flavour named $namespaced_name: $dead";
    return;
  }
  
  my $arguments_def_str = join ", ", map {$_->[0].' '.$_->[1]} @$arguments;
  my $arguments_use_str = join ", ", map {$_->[1]} @$arguments;
  
  if ("$spelling" eq "$namespaced_name") {
    
    $self->xs_file->print(<<END);

$return_type_c
$spelling($arguments_def_str);

END
  } elsif ($flavour eq 'destructor') {
    # Just ignore it for now.

  } elsif ($flavour eq 'function' and $return_type_c eq 'void') {
    $self->xs_file->print(<<END);

void
$spelling($arguments_def_str)
 CODE:
  $namespaced_name($arguments_use_str);

END
  } elsif ($flavour eq 'method' and $return_type_c eq 'void') {
    $self->xs_file->print(<<END);

void
$spelling($arguments_def_str)
 CODE:
  THIS->$spelling($arguments_use_str);

END
  } elsif ($return_type_c eq 'void') {
    die "flavour=$flavour, returning void";
  } elsif ($flavour eq 'function') {
    $self->xs_file->print(<<END);

$return_type_c
$spelling($arguments_def_str)
 CODE:
  RETVAL = $namespaced_name($arguments_use_str);
 OUTPUT:
  RETVAL

END
  } elsif ($flavour eq 'method') {
    $self->xs_file->print(<<END);

$return_type_c
$spelling($arguments_def_str)
 CODE:
  RETVAL = THIS->$spelling($arguments_use_str);
 OUTPUT:
  RETVAL

END
  } elsif ($flavour eq 'constructor') {
    $self->xs_file->print(<<END);

$return_type_c
__new($arguments_def_str)
 CODE:
  RETVAL = new $return_type_c($arguments_use_str);
 OUTPUT:
  RETVAL

END
  } elsif ($flavour eq 'conversion') {
    my $local_name = $return_type_c;
    $local_name =~ s/ \*/_pointer/;
    $local_name =~ s/::/_coloncolon_/g;
    $local_name = "__convert_to_$local_name";

    $self->xs_file->print(<<END);

$return_type_c
$local_name($arguments_def_str)
 CODE:
  RETVAL = $return_type_c($arguments_use_str);
 OUTPUT:
  RETVAL

END
  } else {
    warn "Non-easy function-like of flavour $flavour";
  }
}

sub handle_translation_unit {
  my ($self, $tu, $todo) = @_;
  
  my $in_macro;
  
  $tu->{cursor}->visitChildren(sub {
                                 my ($cursor, $parent) = @_;

                                 #say "Kind: ", $cursor->getCursorKind;
                                 #say "Kind: ", $cursor_kinds->{$cursor->getCursorKind};

                                 my $location = $cursor->getCursorLocation;
                                 #print "Location: $location\n";
                                 #print "Location: $$location\n";
                                 my $filename = $location->getPresumedLocationFilename;

                                 return 1 unless $filename =~ $self->{include_regex};

                                 #print "At $filename\n";

                                 my $kind_names_raw = <<'END';
/* Declarations */
/**
* \brief A declaration whose specific kind is not exposed via this
* interface.
*
* Unexposed declarations have the same operations as any other kind
* of declaration; one can extract their location information,
* spelling, find their definitions, etc. However, the specific kind
* of the declaration is not reported.
*/
CXCursor_UnexposedDecl                 = 1,
/** \brief A C or C++ struct. */
CXCursor_StructDecl                    = 2,
/** \brief A C or C++ union. */
CXCursor_UnionDecl                     = 3,
/** \brief A C++ class. */
CXCursor_ClassDecl                     = 4,
/** \brief An enumeration. */
CXCursor_EnumDecl                      = 5,
/**
* \brief A field (in C) or non-static data member (in C++) in a
* struct, union, or C++ class.
*/
CXCursor_FieldDecl                     = 6,
/** \brief An enumerator constant. */
CXCursor_EnumConstantDecl              = 7,
/** \brief A function. */
CXCursor_FunctionDecl                  = 8,
/** \brief A variable. */
CXCursor_VarDecl                       = 9,
/** \brief A function or method parameter. */
CXCursor_ParmDecl                      = 10,
/** \brief An Objective-C @interface. */
CXCursor_ObjCInterfaceDecl             = 11,
/** \brief An Objective-C @interface for a category. */
CXCursor_ObjCCategoryDecl              = 12,
/** \brief An Objective-C @protocol declaration. */
CXCursor_ObjCProtocolDecl              = 13,
/** \brief An Objective-C @property declaration. */
CXCursor_ObjCPropertyDecl              = 14,
/** \brief An Objective-C instance variable. */
CXCursor_ObjCIvarDecl                  = 15,
/** \brief An Objective-C instance method. */
CXCursor_ObjCInstanceMethodDecl        = 16,
/** \brief An Objective-C class method. */
CXCursor_ObjCClassMethodDecl           = 17,
/** \brief An Objective-C @implementation. */
CXCursor_ObjCImplementationDecl        = 18,
/** \brief An Objective-C @implementation for a category. */
CXCursor_ObjCCategoryImplDecl          = 19,
/** \brief A typedef */
CXCursor_TypedefDecl                   = 20,
/** \brief A C++ class method. */
CXCursor_CXXMethod                     = 21,
/** \brief A C++ namespace. */
CXCursor_Namespace                     = 22,
/** \brief A linkage specification, e.g. 'extern "C"'. */
CXCursor_LinkageSpec                   = 23,
/** \brief A C++ constructor. */
CXCursor_Constructor                   = 24,
/** \brief A C++ destructor. */
CXCursor_Destructor                    = 25,
/** \brief A C++ conversion function. */
CXCursor_ConversionFunction            = 26,
/** \brief A C++ template type parameter. */
CXCursor_TemplateTypeParameter         = 27,
/** \brief A C++ non-type template parameter. */
CXCursor_NonTypeTemplateParameter      = 28,
/** \brief A C++ template template parameter. */
CXCursor_TemplateTemplateParameter     = 29,
/** \brief A C++ function template. */
CXCursor_FunctionTemplate              = 30,
/** \brief A C++ class template. */
CXCursor_ClassTemplate                 = 31,
/** \brief A C++ class template partial specialization. */
CXCursor_ClassTemplatePartialSpecialization = 32,
/** \brief A C++ namespace alias declaration. */
CXCursor_NamespaceAlias                = 33,
/** \brief A C++ using directive. */
CXCursor_UsingDirective                = 34,
/** \brief A C++ using declaration. */
CXCursor_UsingDeclaration              = 35,
/** \brief A C++ alias declaration */
CXCursor_TypeAliasDecl                 = 36,
/** \brief An Objective-C @synthesize definition. */
CXCursor_ObjCSynthesizeDecl            = 37,
/** \brief An Objective-C @dynamic definition. */
CXCursor_ObjCDynamicDecl               = 38,
/** \brief An access specifier. */
CXCursor_CXXAccessSpecifier            = 39,

CXCursor_FirstDecl                     = CXCursor_UnexposedDecl,
CXCursor_LastDecl                      = CXCursor_CXXAccessSpecifier,

/* References */
CXCursor_FirstRef                      = 40, /* Decl references */
CXCursor_ObjCSuperClassRef             = 40,
CXCursor_ObjCProtocolRef               = 41,
CXCursor_ObjCClassRef                  = 42,
/**
* \brief A reference to a type declaration.
*
* A type reference occurs anywhere where a type is named but not
* declared. For example, given:
*
* \code
* typedef unsigned size_type;
* size_type size;
* \endcode
*
* The typedef is a declaration of size_type (CXCursor_TypedefDecl),
* while the type of the variable "size" is referenced. The cursor
* referenced by the type of size is the typedef for size_type.
*/
CXCursor_TypeRef                       = 43,
CXCursor_CXXBaseSpecifier              = 44,
/** 
* \brief A reference to a class template, function template, template
* template parameter, or class template partial specialization.
*/
CXCursor_TemplateRef                   = 45,
/**
* \brief A reference to a namespace or namespace alias.
*/
CXCursor_NamespaceRef                  = 46,
/**
* \brief A reference to a member of a struct, union, or class that occurs in 
* some non-expression context, e.g., a designated initializer.
*/
CXCursor_MemberRef                     = 47,
/**
* \brief A reference to a labeled statement.
*
* This cursor kind is used to describe the jump to "start_over" in the 
* goto statement in the following example:
*
* \code
*   start_over:
*     ++counter;
*
*     goto start_over;
* \endcode
*
* A label reference cursor refers to a label statement.
*/
CXCursor_LabelRef                      = 48,

/**
* \brief A reference to a set of overloaded functions or function templates
* that has not yet been resolved to a specific function or function template.
*
* An overloaded declaration reference cursor occurs in C++ templates where
* a dependent name refers to a function. For example:
*
* \code
* template<typename T> void swap(T&, T&);
*
* struct X { ... };
* void swap(X&, X&);
*
* template<typename T>
* void reverse(T* first, T* last) {
*   while (first < last - 1) {
*     swap(*first, *--last);
*     ++first;
*   }
* }
*
* struct Y { };
* void swap(Y&, Y&);
* \endcode
*
* Here, the identifier "swap" is associated with an overloaded declaration
* reference. In the template definition, "swap" refers to either of the two
* "swap" functions declared above, so both results will be available. At
* instantiation time, "swap" may also refer to other functions found via
* argument-dependent lookup (e.g., the "swap" function at the end of the
* example).
*
* The functions \c clang_getNumOverloadedDecls() and 
* \c clang_getOverloadedDecl() can be used to retrieve the definitions
* referenced by this cursor.
*/
CXCursor_OverloadedDeclRef             = 49,

CXCursor_LastRef                       = CXCursor_OverloadedDeclRef,

/* Error conditions */
CXCursor_FirstInvalid                  = 70,
CXCursor_InvalidFile                   = 70,
CXCursor_NoDeclFound                   = 71,
CXCursor_NotImplemented                = 72,
CXCursor_InvalidCode                   = 73,
CXCursor_LastInvalid                   = CXCursor_InvalidCode,

/* Expressions */
CXCursor_FirstExpr                     = 100,

/**
* \brief An expression whose specific kind is not exposed via this
* interface.
*
* Unexposed expressions have the same operations as any other kind
* of expression; one can extract their location information,
* spelling, children, etc. However, the specific kind of the
* expression is not reported.
*/
CXCursor_UnexposedExpr                 = 100,

/**
* \brief An expression that refers to some value declaration, such
* as a function, varible, or enumerator.
*/
CXCursor_DeclRefExpr                   = 101,

/**
* \brief An expression that refers to a member of a struct, union,
* class, Objective-C class, etc.
*/
CXCursor_MemberRefExpr                 = 102,

/** \brief An expression that calls a function. */
CXCursor_CallExpr                      = 103,

/** \brief An expression that sends a message to an Objective-C
object or class. */
CXCursor_ObjCMessageExpr               = 104,

/** \brief An expression that represents a block literal. */
CXCursor_BlockExpr                     = 105,

/** \brief An integer literal.
*/
CXCursor_IntegerLiteral                = 106,

/** \brief A floating point number literal.
*/
CXCursor_FloatingLiteral               = 107,

/** \brief An imaginary number literal.
*/
CXCursor_ImaginaryLiteral              = 108,

/** \brief A string literal.
*/
CXCursor_StringLiteral                 = 109,

/** \brief A character literal.
*/
CXCursor_CharacterLiteral              = 110,

/** \brief A parenthesized expression, e.g. "(1)".
*
* This AST node is only formed if full location information is requested.
*/
CXCursor_ParenExpr                     = 111,

/** \brief This represents the unary-expression's (except sizeof and
* alignof).
*/
CXCursor_UnaryOperator                 = 112,

/** \brief [C99 6.5.2.1] Array Subscripting.
*/
CXCursor_ArraySubscriptExpr            = 113,

/** \brief A builtin binary operation expression such as "x + y" or
* "x <= y".
*/
CXCursor_BinaryOperator                = 114,

/** \brief Compound assignment such as "+=".
*/
CXCursor_CompoundAssignOperator        = 115,

/** \brief The ?: ternary operator.
*/
CXCursor_ConditionalOperator           = 116,

/** \brief An explicit cast in C (C99 6.5.4) or a C-style cast in C++
* (C++ [expr.cast]), which uses the syntax (Type)expr.
*
* For example: (int)f.
*/
CXCursor_CStyleCastExpr                = 117,

/** \brief [C99 6.5.2.5]
*/
CXCursor_CompoundLiteralExpr           = 118,

/** \brief Describes an C or C++ initializer list.
*/
CXCursor_InitListExpr                  = 119,

/** \brief The GNU address of label extension, representing &&label.
*/
CXCursor_AddrLabelExpr                 = 120,

/** \brief This is the GNU Statement Expression extension: ({int X=4; X;})
*/
CXCursor_StmtExpr                      = 121,

/** \brief Represents a C1X generic selection.
*/
CXCursor_GenericSelectionExpr          = 122,

/** \brief Implements the GNU __null extension, which is a name for a null
* pointer constant that has integral type (e.g., int or long) and is the same
* size and alignment as a pointer.
*
* The __null extension is typically only used by system headers, which define
* NULL as __null in C++ rather than using 0 (which is an integer that may not
* match the size of a pointer).
*/
CXCursor_GNUNullExpr                   = 123,

/** \brief C++'s static_cast<> expression.
*/
CXCursor_CXXStaticCastExpr             = 124,

/** \brief C++'s dynamic_cast<> expression.
*/
CXCursor_CXXDynamicCastExpr            = 125,

/** \brief C++'s reinterpret_cast<> expression.
*/
CXCursor_CXXReinterpretCastExpr        = 126,

/** \brief C++'s const_cast<> expression.
*/
CXCursor_CXXConstCastExpr              = 127,

/** \brief Represents an explicit C++ type conversion that uses "functional"
* notion (C++ [expr.type.conv]).
*
* Example:
* \code
*   x = int(0.5);
* \endcode
*/
CXCursor_CXXFunctionalCastExpr         = 128,

/** \brief A C++ typeid expression (C++ [expr.typeid]).
*/
CXCursor_CXXTypeidExpr                 = 129,

/** \brief [C++ 2.13.5] C++ Boolean Literal.
*/
CXCursor_CXXBoolLiteralExpr            = 130,

/** \brief [C++0x 2.14.7] C++ Pointer Literal.
*/
CXCursor_CXXNullPtrLiteralExpr         = 131,

/** \brief Represents the "this" expression in C++
*/
CXCursor_CXXThisExpr                   = 132,

/** \brief [C++ 15] C++ Throw Expression.
*
* This handles 'throw' and 'throw' assignment-expression. When
* assignment-expression isn't present, Op will be null.
*/
CXCursor_CXXThrowExpr                  = 133,

/** \brief A new expression for memory allocation and constructor calls, e.g:
* "new CXXNewExpr(foo)".
*/
CXCursor_CXXNewExpr                    = 134,

/** \brief A delete expression for memory deallocation and destructor calls,
* e.g. "delete[] pArray".
*/
CXCursor_CXXDeleteExpr                 = 135,

/** \brief A unary expression.
*/
CXCursor_UnaryExpr                     = 136,

/** \brief ObjCStringLiteral, used for Objective-C string literals i.e. "foo".
*/
CXCursor_ObjCStringLiteral             = 137,

/** \brief ObjCEncodeExpr, used for in Objective-C.
*/
CXCursor_ObjCEncodeExpr                = 138,

/** \brief ObjCSelectorExpr used for in Objective-C.
*/
CXCursor_ObjCSelectorExpr              = 139,

/** \brief Objective-C's protocol expression.
*/
CXCursor_ObjCProtocolExpr              = 140,

/** \brief An Objective-C "bridged" cast expression, which casts between
* Objective-C pointers and C pointers, transferring ownership in the process.
*
* \code
*   NSString *str = (__bridge_transfer NSString *)CFCreateString();
* \endcode
*/
CXCursor_ObjCBridgedCastExpr           = 141,

/** \brief Represents a C++0x pack expansion that produces a sequence of
* expressions.
*
* A pack expansion expression contains a pattern (which itself is an
* expression) followed by an ellipsis. For example:
*
* \code
* template<typename F, typename ...Types>
* void forward(F f, Types &&...args) {
*  f(static_cast<Types&&>(args)...);
* }
* \endcode
*/
CXCursor_PackExpansionExpr             = 142,

/** \brief Represents an expression that computes the length of a parameter
* pack.
*
* \code
* template<typename ...Types>
* struct count {
*   static const unsigned value = sizeof...(Types);
* };
* \endcode
*/
CXCursor_SizeOfPackExpr                = 143,

CXCursor_LastExpr                      = CXCursor_SizeOfPackExpr,

/* Statements */
CXCursor_FirstStmt                     = 200,
/**
* \brief A statement whose specific kind is not exposed via this
* interface.
*
* Unexposed statements have the same operations as any other kind of
* statement; one can extract their location information, spelling,
* children, etc. However, the specific kind of the statement is not
* reported.
*/
CXCursor_UnexposedStmt                 = 200,

/** \brief A labelled statement in a function. 
*
* This cursor kind is used to describe the "start_over:" label statement in 
* the following example:
*
* \code
*   start_over:
*     ++counter;
* \endcode
*
*/
CXCursor_LabelStmt                     = 201,

/** \brief A group of statements like { stmt stmt }.
*
* This cursor kind is used to describe compound statements, e.g. function
* bodies.
*/
CXCursor_CompoundStmt                  = 202,

/** \brief A case statment.
*/
CXCursor_CaseStmt                      = 203,

/** \brief A default statement.
*/
CXCursor_DefaultStmt                   = 204,

/** \brief An if statement
*/
CXCursor_IfStmt                        = 205,

/** \brief A switch statement.
*/
CXCursor_SwitchStmt                    = 206,

/** \brief A while statement.
*/
CXCursor_WhileStmt                     = 207,

/** \brief A do statement.
*/
CXCursor_DoStmt                        = 208,

/** \brief A for statement.
*/
CXCursor_ForStmt                       = 209,

/** \brief A goto statement.
*/
CXCursor_GotoStmt                      = 210,

/** \brief An indirect goto statement.
*/
CXCursor_IndirectGotoStmt              = 211,

/** \brief A continue statement.
*/
CXCursor_ContinueStmt                  = 212,

/** \brief A break statement.
*/
CXCursor_BreakStmt                     = 213,

/** \brief A return statement.
*/
CXCursor_ReturnStmt                    = 214,

/** \brief A GNU inline assembly statement extension.
*/
CXCursor_AsmStmt                       = 215,

/** \brief Objective-C's overall @try-@catc-@finall statement.
*/
CXCursor_ObjCAtTryStmt                 = 216,

/** \brief Objective-C's @catch statement.
*/
CXCursor_ObjCAtCatchStmt               = 217,

/** \brief Objective-C's @finally statement.
*/
CXCursor_ObjCAtFinallyStmt             = 218,

/** \brief Objective-C's @throw statement.
*/
CXCursor_ObjCAtThrowStmt               = 219,

/** \brief Objective-C's @synchronized statement.
*/
CXCursor_ObjCAtSynchronizedStmt        = 220,

/** \brief Objective-C's autorelease pool statement.
*/
CXCursor_ObjCAutoreleasePoolStmt       = 221,

/** \brief Objective-C's collection statement.
*/
CXCursor_ObjCForCollectionStmt         = 222,

/** \brief C++'s catch statement.
*/
CXCursor_CXXCatchStmt                  = 223,

/** \brief C++'s try statement.
*/
CXCursor_CXXTryStmt                    = 224,

/** \brief C++'s for (* : *) statement.
*/
CXCursor_CXXForRangeStmt               = 225,

/** \brief Windows Structured Exception Handling's try statement.
*/
CXCursor_SEHTryStmt                    = 226,

/** \brief Windows Structured Exception Handling's except statement.
*/
CXCursor_SEHExceptStmt                 = 227,

/** \brief Windows Structured Exception Handling's finally statement.
*/
CXCursor_SEHFinallyStmt                = 228,

/** \brief The null satement ";": C99 6.8.3p3.
*
* This cursor kind is used to describe the null statement.
*/
CXCursor_NullStmt                      = 230,

/** \brief Adaptor class for mixing declarations with statements and
* expressions.
*/
CXCursor_DeclStmt                      = 231,

CXCursor_LastStmt                      = CXCursor_DeclStmt,

/**
* \brief Cursor that represents the translation unit itself.
*
* The translation unit cursor exists primarily to act as the root
* cursor for traversing the contents of a translation unit.
*/
CXCursor_TranslationUnit               = 300,

/* Attributes */
CXCursor_FirstAttr                     = 400,
/**
* \brief An attribute whose specific kind is not exposed via this
* interface.
*/
CXCursor_UnexposedAttr                 = 400,

CXCursor_IBActionAttr                  = 401,
CXCursor_IBOutletAttr                  = 402,
CXCursor_IBOutletCollectionAttr        = 403,
CXCursor_CXXFinalAttr                  = 404,
CXCursor_CXXOverrideAttr               = 405,
CXCursor_AnnotateAttr                  = 406,
CXCursor_LastAttr                      = CXCursor_AnnotateAttr,

/* Preprocessing */
CXCursor_PreprocessingDirective        = 500,
CXCursor_MacroDefinition               = 501,
CXCursor_MacroExpansion                = 502,
CXCursor_MacroInstantiation            = CXCursor_MacroExpansion,
CXCursor_InclusionDirective            = 503,
CXCursor_FirstPreprocessing            = CXCursor_PreprocessingDirective,
CXCursor_LastPreprocessing             = CXCursor_InclusionDirective
END

                                 my $cursor_kinds;
                                 for my $line (split "\n", $kind_names_raw) {
                                   #print "$line\n";
                                   next unless $line =~ m/^\s*CXCursor_([A-Za-z]+)\s* = (\d+),$/;
                                   #print "1: $1, 2: $2\n";

                                   $cursor_kinds->{$2} = $1;
                                 }

                                 my $kind_str = $cursor_kinds->{$cursor->getCursorKind};
                                 given ($kind_str) {
                                   # Trying for a smaller list of things that we are interested in,
                                   # and then we can go from there, recursing down the things that are
                                   # neccessary to actually use it.
                                   when (['ClassDecl',
                                          'FunctionDecl',
                                          'Constructor',
                                          'CXXMethod',
                                          'ConversionFunction',
                                          'Destructor',
                                          'VarDecl',
                                          'MacroDefinition',
                                         ]) {
                                     # Classes go here, and structs do not, because classes
                                     # traditionally contain methods, and structs do not.

                                     push @$todo, {cursor => $cursor, kind_was=>$kind_str, why => 'translation-unit top-level'};

                                     return 1;
                                   }

                                   when ('MacroExpansion') {
                                     # This is not, as one might think, where the bar of #define foo bar goes, but rather is a place where a macro is used.
                                     return 2;
                                   }

                                   when ([
                                          'ClassTemplate',
                                          'OverloadedDeclRef',
                                          'StructDecl',
                                          'UnionDecl',
                                          'EnumDecl',
                                          'TypedefDecl',
                                          'ClassTemplatePartialSpecialization',
                                          'FunctionTemplate',
                                         ]) {
                                     return 1;
                                   }

                                   when (['UnexposedDecl', 'Namespace', 'UsingDeclaration', 'UsingDirective', 'NamespaceRef', 'InclusionDirective']) {
                                     # WTF is the difference between a "UsingDeclaration" and a "UsingDirective" anyway?
                                     return 2;
                                   }

                                   default {
                                     die "Don't know what to do with a $kind_str in handle_translationunit (from $filename)";
                                   }
                                 }
                               }
                              );
}

sub handle_record {
  my ($self, $todo_item, $todo) = @_;

  my $own_cursor = $todo_item->{cursor};
  my $own_type = $own_cursor->getCursorType;
  my $spelling = $own_cursor->getCursorSpelling;
  say "spelling: $spelling";

  push @$todo, {
                type => $own_type,
                why => "type of record declaration from (".$todo_item->{why}.")",
               };

  my $own_c_name = $self->type_to_c_name($own_type);
  say "own c name: $own_c_name";
  my $own_perl_name = $self->type_to_perl_name($own_type);
  say "own perl name: $own_perl_name";

  my $access;
  given ($own_cursor->getCursorKind) {
    when ([2,3]) {
      $access = 'public';
    }
    when (4) {
      $access = 'private';
    }
    default {
      die "Don't know default access for a $_";
    }
  }

  say "access: $access\n";

  $own_cursor->visitChildren(sub {
        my ($sub_cursor) = @_;

        #say "Child of record type\n";

        my $sub_kind = $sub_cursor->getCursorKind;

        #say "sub-kind: $sub_kind";
        given ($sub_kind) {
          when (39) {
            # CXXAccessSpecifier
            my $new_access = $sub_cursor->getCXXAccessSpecifier();
            given ($new_access) {
              when (0) {
                die "Huh, new access level is invalid?"
              }
              when (1) {
                $access = 'public';
              }
              when (2) {
                $access = 'protected';
              }
              when (3) {
                $access = 'private';
              }
              default {
                die "New access level $new_access is unknown";
              }
            }
            say "access level changed to $access";
          }
          when (1) {
            warn "Unexposed declaration in record";
          }
          when ([
                 6,  # field
                 9,  # var decl (static method)
                 21, # method
                 24, # constructor
                 25, # destructor
                 26, # conversion function
                 #30, # function template
                ]) {
            push @$todo, {
                          cursor => $sub_cursor,
                          access => $access,
                          parent_class => $own_type,
                          why => 'record element',
                         };
          }
          when ([2,  # struct
                 3,  # union
                 4,  # class
                 5,  # enum
                 10, # typedef
                 20, # typedef
                ]) {
            # We explicltly *don't* follow these; if they are needed, we should pick them up when a method, etc, references one of them.
          }
          when (30) {
            # FunctionTemplate -- a template that takes a templated type:
            # template<typename _Tp> explicit Mat(const vector<_Tp>& vec, bool copyData=false);
            # Ignore (for now?)
          }
          when (31) {
            # I have bugger-all idea wtf this is, to be perfectly honest.
          }
          when (35) {
            # using declration, which I think is ignorable... I'm honestly not sure
            # what that means in C++.

            #class DeclContextLookupResult
            #    : public std::pair<NamedDecl**,NamedDecl**> {
            #    
            #	using std::pair<NamedDecl**,NamedDecl**>::operator=;
            #};
          }
          when (43) {
            # TypeRef -- a reference to another type, which has been declared earlier.
            # template<> class DataDepth<uchar> { public: enum { value = CV_8U, fmt=(int)'u' }; };
            # This confuses me.
          }
          when (44) {
            my $base_perl_name = $self->type_to_perl_name($sub_cursor->getCursorType);
            say "FIXME: (additional) base class of $own_perl_name is $base_perl_name";
            push @$todo, {why => "base class of $own_perl_name",
                          type => $sub_cursor->getCursorType,
                         };
          }
            
          default {
            my $filename = $sub_cursor->getCursorLocation->getPresumedLocationFilename;
            my $line = $sub_cursor->getCursorLocation->getPresumedLocationLine;
            die "sub-kind $sub_kind in record at $filename line $line";
          }
	}
	
	return 1;
      });
}

sub namespaced_name {
    my ($self, $cursor) = @_;
    confess "namespaced_name called without two parameters -- it's a method, not a function" if @_ < 2;
    
    my $kind = $cursor->getCursorKind;
    if ($kind == 1) {
	# unexposed decl
	return undef;
    }

    my $spelling = $cursor->getCursorSpelling;
    if ($kind == 71) {
      # CXCursor_NoDeclFound
      return undef;
    }
    if ($kind ~~ [3, 5] and not $spelling) {
      # anonymous union / enum
      return undef;
    }
    if (not $spelling) {
	die "namespaced_name of a unspellable beast of kind $kind?";
    }

    $spelling =~ s/\bcv\b/opencv_cv/g
      if $self->opencv_hack;

    my $semantic_parent = $cursor->getCursorSemanticParent;
    if (not $semantic_parent) {
	die "namespaced_name of something with no parent?";
    }
    if (not defined $self->namespaced_name($semantic_parent)) {
	return $spelling;
    }
    return $self->namespaced_name($semantic_parent) . "::" . $spelling;
}

sub type_to_c_name {
  my ($self, $type) = @_;
  confess "type_to_c_name called with wrong number of arguments" if @_ != 2;

  if (not $type) {
    return undef;
  }

  my $type_kind = $type->getTypeKind;

  #print STDERR "Type kind: $type_kind\n";
  #my $spelling = $type->getTypeDeclaration->getCursorSpelling;
  my $spelling = $self->namespaced_name($type->getTypeDeclaration);
  #print STDERR "Spelling: $spelling\n";

  my $const = $type->isConstQualifiedType ? "const " : "";
  #print STDERR "Const: $const\n";

  state $simple_type_kinds = {
                              2 => 'void',
                              3 => 'bool',
                              # http://clang-developers.42468.n3.nabble.com/llibclang-CXTypeKind-char-types-td3754411.html
                              4 => 'unsigned char',
			      5 => 'unsigned char',
			      8 => 'unsigned short',
                              9 => "unsigned int",
			      10 => 'unsigned long',
                              11 => "unsigned long long",
                              # http://clang-developers.42468.n3.nabble.com/llibclang-CXTypeKind-char-types-td3754411.html
                              # This is a a char, which happens to be signed.
                              13 => "char",
                              16 => "short",
                              17 => "int",
			      18 => 'long',
                              19 => "long long",
                              21 => 'float',
                              22 => "double"
                             };
  if (exists $simple_type_kinds->{$type_kind}) {
    return $const.$simple_type_kinds->{$type_kind};
  } elsif ($type_kind == 105 and $spelling) {
    # Record type, could be a struct, could be a class.  Unfortunately, this is one of the few places where it matters.
    my $decl_kind = $type->getTypeDeclaration->getCursorKind;
    given ($decl_kind) {
      when (2) {
        ##   CXCursor_StructDecl                    = 2,
        return "${const}struct $spelling";
      }
      when (3) {
        # CXCursor_UnionDecl
        return "${const}union $spelling";
      }
      when (4) {
        # CXCursor_ClassDecl
        return "${const}$spelling";
      }
      default {
        die "Unknown decl-kind of record type: $decl_kind";
      }
    }

  } elsif ($type_kind == 107 and $spelling) {
    # typedef, no tag.
    return $const.$spelling;

  } elsif ($type_kind == 1 and $spelling) {
    my $decl_kind = $type->getTypeDeclaration->getCursorKind;
    
    given ($decl_kind) {
      when (2) {
        return "${const}struct $spelling";
      }
      
      when (4) {
        # C++ doesn't have an explicit tag on uses of a class.
        return "$const$spelling";
      }

      when (5) {
        return "${const}enum $spelling";
      }

      when (20) {
        # typedef
        return "$const$spelling";
      }

      when (31) {
        return "${const}typename<$spelling>";
      }

      default {
        die "type_to_c_name of decl_kind $decl_kind spelled $spelling";
      }
    }

  } elsif ($type_kind == 1) {
    # /**
    #  * \brief A type whose specific kind is not exposed via this
    #  * interface.
    #  */
    # CXType_Unexposed = 1,
    # This seems to be used for pointers to functions.
    my $filename = $type->getTypeDeclaration->getCursorLocation->getPresumedLocationFilename;
    my $line = $type->getTypeDeclaration->getCursorLocation->getPresumedLocationLine;

    warn "Unexposed nameless type from $filename line $line";
    #return "nameless_unexposed_type_from_${filename}_line_$line";

    return undef;
  } elsif ($type_kind == 106 and $spelling) {
    # spelled enum
    return "${const}enum $spelling";
  } elsif ($spelling) {
    die "Unhandled spelled $type_kind spelled $spelling";
  } elsif ($type_kind == 101) {
    # pointer
    my $inner_type = $self->type_to_c_name($type->getPointeeType);
    if (not defined $inner_type) {
      warn "Pointer to undefined?";
      return undef;
    }
    return "$const${inner_type}*";
  } elsif ($type_kind == 103) {
    #   CXType_LValueReference = 103,
    # pointer
    my $inner_type = $self->type_to_c_name($type->getPointeeType);
    if (not defined $inner_type) {
      warn "&-reference to undefined type?";
      return undef;
    }
    #return $inner_type."&";
    # While the name of a type might need an &, the type of an argument... oh, hell, I think it may need...
    return "${const}$inner_type";

  } elsif ($type_kind == 105) {
      # CXType_Record -- this is something like typedef struct {} foo.
      # Ideally, we shouldn't have gotten here, we should have used
      # the name that it's typedefed to.
      warn "Anonymous struct";
      return undef;

  } elsif ($type_kind == 106) {
    # /usr/include/opencv/cxcore.hpp line 207
    my $filename = $type->getTypeDeclaration->getCursorLocation->getPresumedLocationFilename;
    my $line = $type->getTypeDeclaration->getCursorLocation->getPresumedLocationLine;
    warn "anon enum from $filename line $line";

    return undef;
  } elsif ($type_kind == 111) {
    return 'FIXME_paren_expr';

  } elsif ($type_kind == 112) {
    my $element_type_c = $self->type_to_c_name($type->getArrayElementType);
    my $array_size = $type->getArraySize;

    return "${const}typeof(${element_type_c}[${array_size}])";

  } else {
    my $filename = $type->getTypeDeclaration->getCursorLocation->getPresumedLocationFilename;
    my $line = $type->getTypeDeclaration->getCursorLocation->getPresumedLocationLine;

    carp "Don't know how to convert type to c name, type_kind = $type_kind from $filename line $line";
    return undef;
  }
}

sub type_to_perl_name {
  my ($self, $type) = @_;
  confess "type_to_perl_name called with wrong number of arguments"
    if @_ != 2;
  my $c_name = $self->type_to_c_name($type);
  return undef if not defined $c_name;

  my $perl_name;
  my $base = $self->base_module;
  $perl_name = "${base}::${c_name}";
  #if ($c_name =~ m/^Cv(.*)/) {
  #  $perl_name = "::$1";
  #} elsif ($c_name ~~ qr/^(Ipl.*|Mat|Exception|WString)/) {
  #  $perl_name = "OpenCV::$1";
  #} elsif ($c_name ~~ [qr/(void|int|uchar|schar|char|double|float|string)[&*]*/]) {
  #  $perl_name = "OpenCV::C_Internals::$1";
  #} else {
  #  $perl_name = "OpenCV::$c_name";
  #  #die "Don't know perl name for c name $c_name";
  #}

  $perl_name =~ s/ /_/g;
  $perl_name =~ s/\*/_Pointer/g;

  return $perl_name;
}

'Woof!';
