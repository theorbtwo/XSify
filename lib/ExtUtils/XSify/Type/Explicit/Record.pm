package ExtUtils::XSify::Type::Explicit::Record;
use 5.10.0;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Explicit';

sub fields {
  my ($self) = @_;

  my $access = $self->initial_access;

  my @fields;

  $self->cursor->visitChildren
    (sub {
       my ($cursor) = @_;

       my $kind = $cursor->getCursorKind;

       given ($kind) {
         when ([2,  # struct
                5,  # enum
                6,  # field
               ]) {
           my $name = $cursor->getCursorSpelling;
           my $location = $self->location;
           push @fields, {access => $access,
                          name => $cursor->getCursorSpelling,
                          cursor => $cursor,
                          type => ExtUtils::XSify::Type->factory(parent_cursor => $cursor,
                                                                 location => "field(ish) $name of $location",
                                                                 type => $cursor->getCursorType),
                         };
         }
         
         when ([
                21, # method
                24, # constructor
                25, # destructor
                26, # conversion
               ]) {
         }

         when (20) {
           # Typedef.  Ignore; things that use the typedef will point to this for us.
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
           my $spelling = $cursor->getCursorSpelling;
           print "In fields, self=$self\n";
           die "Don't know child kind $kind of a record (".$self->location."), spelling='$spelling'";
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
