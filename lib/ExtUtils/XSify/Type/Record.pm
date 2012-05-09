package ExtUtils::XSify::Type::Record;
use 5.10.0;
use Moose;
use MooseX::StrictConstructor;

has 'type',
  is => 'ro',
  required => 1,
  isa => 'CLang::Type'
  ;

has 'decl',
  is => 'ro',
  lazy => 1,
  default => sub {
    my ($self) = @_;

    $self->type->getTypeDeclaration;
  };

sub to_do_mark {
  my ($self) = @_;

  return "record:".$self->decl->getCursorUSR;
}

sub fields {
  my ($self) = @_;

  my $access = $self->initial_access;

  my @fields;

  $self->decl->visitChildren
    (sub {
       my ($cursor) = @_;

       my $kind = $cursor->getCursorKind;

       given ($kind) {

         when ([5,  # enum
                6,  # field
               ]) {
           push @fields, {access => $access,
                          name => $cursor->getCursorSpelling,
                          cursor => $cursor,
                          type => ExtUtils::XSify::Type->new(parent_cursor => $cursor,
                                                             type => $cursor->getCursorType),
                         };
         }
         
         when ([
                21, # method
                24, # constructor
                25, # destructor
                25, # conversion
               ]) {
         }
         
         when (30) {
           # FunctionTemplate
         }

         when (39) {
           # CXXAccessSpecifier
           my $new_access = $cursor->getCXXAccessSpecifier;
           $access = ['invalid',
                      'public',
                      'protected',
                      'private']->[$new_access];
         }

         when (44) {
           # CXXBaseSpecifier
         }

         default {
           die "Don't know child kind $kind of a record (".$self->location.")";
         }
       }

       return 1;
     });

  return @fields;
}

sub more_to_do {
  my ($self) = @_;

  map {$_->{type}} $self->fields;
}

sub make_xs {
  # Should probably do something here.
}

"one from column a, one from column b";
