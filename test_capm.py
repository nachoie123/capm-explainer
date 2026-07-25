"""Check mínimo sin red: aritmética CAPM y Gordon."""
from capm import expected_market_return  # noqa
# CAPM puro: E[R] = rf + beta*(rm-rf)
rf, beta, rm = 0.047, 0.35, 0.05
er = rf + beta * (rm - rf)
assert abs(er - 0.04805) < 1e-6, er
# Gordon: E[Rm] = dy*(1+g)+g  -> con dy=0.01, g=0.04 => 0.0504
assert abs((0.01 * 1.04 + 0.04) - 0.0504) < 1e-9
print("ok")
