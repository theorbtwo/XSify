package ExtUtils::XSify::Type::Explicit::Enum;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Explicit';

sub more_to_do {
}

sub make_xs {
  my ($self, $xs, $pm, $typemap) = @_;

  ExtUtils::XSify::Symbol::Function::dump_visit_tree($self->cursor);

  $self->cursor->visitChildren
    (sub {
       my ($cursor) = @_;
       my $kind = $cursor->getCursorKind;

       if ($kind != 7) {
         die "Strange child of an enum, cursor kind = $kind at ".$self->location;
       }

       my $name = $cursor->getCursorSpelling;

       push @{$xs->{$self->perl_module}}, <<"END";
int
$name()
 CODE:
  RETVAL = $name;
 OUTPUT:
  RETVAL
END
       
       return 1;
     });
}

'1, 2, 5';
