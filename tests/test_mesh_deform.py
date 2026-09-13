from PIL import Image, ImageDraw

from mesh_deform import warp_rgba, warp_bone_weighted_rgba


def test_tps_identity_is_pixel_identical():
    im = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((20, 20, 44, 44), fill=(255, 50, 50, 255))
    joints = {
        'a': {'x': .3, 'y': .3},
        'b': {'x': .7, 'y': .3},
        'c': {'x': .5, 'y': .7},
    }
    out = warp_rgba(im, joints, joints)
    assert out.tobytes() == im.tobytes()


def test_tps_moves_art_with_joint_target():
    im = Image.new('RGBA', (120, 120), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((42, 42, 58, 58), fill=(255, 255, 255, 255))
    rest = {
        'root': {'x': .30, 'y': .42},
        'mid': {'x': .42, 'y': .42},
        'end': {'x': .50, 'y': .42},
        'stabilizer': {'x': .50, 'y': .72},
    }
    posed = {name: dict(point) for name, point in rest.items()}
    posed['end'] = {'x': .64, 'y': .32}
    out = warp_rgba(im, rest, posed, regularization=1e-5)
    assert out.tobytes() != im.tobytes()
    assert out.getbbox() is not None
    assert out.size == im.size


def test_bone_weighted_identity_is_pixel_identical():
    im = Image.new('RGBA', (96, 96), (0, 0, 0, 0))
    ImageDraw.Draw(im).rectangle((18, 32, 78, 64), fill=(40, 180, 240, 255))
    joints = {
        'a': {'x': .25, 'y': .50},
        'b': {'x': .50, 'y': .50},
        'c': {'x': .75, 'y': .50},
    }
    bones = [['a','b'], ['b','c']]
    out = warp_bone_weighted_rgba(im, joints, joints, bones)
    assert out.tobytes() == im.tobytes()


def test_bone_weighted_is_local_not_global_rubber_sheet():
    im = Image.new('RGBA', (160, 120), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.rectangle((22, 44, 74, 58), fill=(240, 60, 60, 255))
    draw.rectangle((128, 46, 144, 62), fill=(60, 240, 80, 255))
    rest = {
        'shoulder': {'x': .46, 'y': .43},
        'elbow': {'x': .30, 'y': .43},
        'wrist': {'x': .14, 'y': .43},
        'torso_a': {'x': .50, 'y': .30},
        'torso_b': {'x': .50, 'y': .72},
    }
    posed = {name: dict(point) for name, point in rest.items()}
    posed['wrist'] = {'x': .16, 'y': .22}
    posed['elbow'] = {'x': .31, 'y': .31}
    bones = [['shoulder','elbow'], ['elbow','wrist'], ['torso_a','torso_b']]
    out = warp_bone_weighted_rgba(
        im, rest, posed, bones,
        influence_radius=.12,
        identity_weight=.22,
        max_influences=2,
        interpolation='linear',
    )
    assert out.tobytes() != im.tobytes()
    before = im.crop((124, 42, 150, 68))
    after = out.crop((124, 42, 150, 68))
    assert sum(after.getchannel('A').getdata()) > sum(before.getchannel('A').getdata()) * 0.5
