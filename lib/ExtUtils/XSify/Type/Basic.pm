package ExtUtils::XSify::Type::Basic;
use Moose;

sub to_do_mark {
  ref shift;
}

sub more_to_do {
  ();
}

sub make_xs {
}

"Not beginner's all-purpose symbolic instruction code";
