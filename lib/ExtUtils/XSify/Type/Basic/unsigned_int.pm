package ExtUtils::XSify::Type::Basic::unsigned_int;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Basic';

sub output_name {
  return 'unsigned int';
}

'unsigned int';
