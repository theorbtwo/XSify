package ExtUtils::XSify::TranslationUnit;
use 5.10.0;
use warnings;
use strict;
use Moose;
use MooseX::StrictConstructor;
use ExtUtils::XSify::FunctionDecl;
use ExtUtils::XSify::VarDecl;

has 'translation_unit',
  is => 'ro',
  isa => 'CLang::TranslationUnit',
  handles => ['getTranslationUnitCursor']
  ;

has 'cursor',
  is => 'ro',
  required => 0,
  lazy => 1,
  default => sub {
    $_[0]->getTranslationUnitCursor;
  };

sub to_do_mark {
  my ($self) = @_;

  $self->cursor->getCursorUSR;
}

sub more_to_do {
  my ($self) = @_;

  my @stuff;
  $self->cursor->visitChildren(sub {
                                 my ($cursor, $parent_cursor) = @_;

                                 my $usr = $cursor->getCursorUSR;
                                 my $kind = $cursor->getCursorKind;
                                 
                                 my $presumed_filename = $cursor->getCursorLocation->getPresumedLocationFilename;
                                 # FIXME: tie to config file.
                                 return 1 unless $presumed_filename =~ m/opencv/i;

                                 given ($kind) {
                                   when ([1,   # UnexposedDecl (?)
                                          2,   # StructDecl
                                          3,   # UnionDecl
                                          5,   # EnumDecl

                                          20,  # TypedefDecl
                                          34,  # UsingDirective
                                          35,  # UsingDeclaration

                                          400, # UnexposedAttr

                                          501, # MacroDefinition
                                          502, # MacroExpansion
                                          503, # InclusionDirective

                                          # These are the questionable ones.
                                          4,  # ClassDecl
                                          30, # FunctionTemplate
                                          31, # ClassTemplate
                                          32, # ClassTemplatePartialSpecialization
                                         ]) {
                                     return 1;
                                   }

                                   when ([22, # Namespace
                                         ]) {
                                     # Look *inside* these.
                                     return 2;
                                   }

                                   when ([8,  # FunctionDecl
                                          21, # CXXMethod
                                          24, # Constructor
                                          25, # Destructor
                                          26, # ConversionFunction
                                         ]) {
                                     #print "Pushing $usr\n";
                                     my $symbol = ExtUtils::XSify::FunctionDecl->new(cursor => $cursor);
                                     push @stuff, $symbol;
                                     return 1;
                                   }

                                   when ([9]) {
                                     # VarDecl
                                     # print "Pushing $usr\n";
                                     my $symbol = ExtUtils::XSify::VarDecl->new(cursor => $cursor);
                                     push @stuff, $symbol;
                                     return 1;
                                   }

                                   default {
                                     print "USR: $usr\n";
                                     print "Kind: $kind\n";

                                     die "Unhandled kind $kind in symbols";
                                   }
                                 }
                               });

  return @stuff;
}

sub make_xs {
  return;
}

1;
