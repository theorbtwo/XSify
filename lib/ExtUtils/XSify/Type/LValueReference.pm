package ExtUtils::XSify::Type::LValueReference;
use Moose;
use MooseX::StrictConstructor;

has 'type',
  is => 'ro',
  required => 1,
  isa => 'CLang::Type'
  ;

has 'pointee',
  is => 'ro',
  lazy => 1,
  default => sub {
    my ($self) = @_;

    ExtUtils::XSify::Type->new(type => $self->type->getPointeeType,
                               location => "pointee of ".$self->location,
                               parent_cursor => $self->parent_cursor,
                              );
  };

has 'location', is => 'ro';
has 'parent_cursor',
  is => 'ro',
  required => 1,
  isa => 'CLang::Cursor';

sub output_name {
  my ($self) = @_;

  my $pointee = $self->pointee;

  if (!$pointee) {
    return 'void*';
  }

  print "LValueReference output_name, pointee is $pointee\n";

  return $pointee->output_name.'&';
}

sub to_do_mark {
  my ($self) = @_;

  if (!$self->pointee) {
    return 'lvalueref:void&';
  }

  'lvalueref:'.$self->pointee->to_do_mark;
}

sub more_to_do {
  my ($self) = @_;

  $self->pointee;
}

sub xs_name {
  my ($self) = @_;

  my $n = $self->output_name;
  $n =~ s/([^A-Za-z])/sprintf '_%02x', ord $1/ge;
  
  return $n;
}

sub make_xs {
  my ($self, $xs, $pm, $typemap) = @_;

  $typemap->add_typemap(ctype => $self->output_name,
                        xstype => $self->xs_name
                       );

  # These are decidedly non-optimal.

  $typemap->add_inputmap(xstype => $self->xs_name,
                          code => '$var = ($type)SvNV($arg);');

  $typemap->add_outputmap(xstype => $self->xs_name,
                          code => 'sv_setnv($arg, (NV)$arg);');
}

"It's a pointer!  No, it's a value!  No, it's Super-fucked-up!";
