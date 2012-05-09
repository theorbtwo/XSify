package ExtUtils::XSify::Type::Basic::double;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Basic';

sub output_name {
  return 'double';
}

'double';
