package ExtUtils::XSify::Type::Basic::int;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Basic';

sub output_name {
  return 'int';
}

'int';
