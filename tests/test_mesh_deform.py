from PIL import Image, ImageDraw

from mesh_deform import warp_rgba


def test_tps_identity_is_pixel_identical():
    im = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((20, 20, 44, 44), fill=(255, 50, 50, 255))
    joints = {'a': {'x': .3, 'y': .3}, 'b': {'x': .7, 'y': .3}, 'c': {'x': .5, 'y': .7}}
    out = warp_rgba(im, joints, joints)
    assert out.tobytes() == im.tobytes()


def test_tps_moves_art_with_joint_target():
    im = Image.new('RGBA', (120, 120), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((42, 42, 58, 58), fill=(255, 255, 255, 255))
    rest = {
        'root': {'x': .30, 'y': .42}, 'mid': {'x': .42, 'y': .42},
        'end': {'x': .50, 'y': .42}, 'stabilizer': {'x': .50, 'y': .72},
    }
    posed = {name: dict(point) for name, point in rest.items()}
    posed['end'] = {'x': .64, 'y': .32}
    out = warp_rgba(im, rest, posed, regularization=1e-5)
    assert out.tobytes() != im.tobytes()
    assert out.getbbox() is not None
    assert out.size == im.size
