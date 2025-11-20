# Generated manually for BiologiDex multiple animals and image conversion support

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('images', '0002_imageconversion'),
        ('vision', '0002_add_dex_compatible_image_fields'),
    ]

    operations = [
        # Add source_conversion foreign key
        migrations.AddField(
            model_name='analysisjob',
            name='source_conversion',
            field=models.ForeignKey(
                blank=True,
                help_text='Source image conversion (new workflow)',
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='analysis_jobs',
                to='images.imageconversion'
            ),
        ),
        # Make image field nullable (legacy support)
        migrations.AlterField(
            model_name='analysisjob',
            name='image',
            field=models.ImageField(
                blank=True,
                help_text='DEPRECATED: Original uploaded image (legacy workflow)',
                null=True,
                upload_to='vision/analysis/original/%Y/%m/'
            ),
        ),
        # Add post_conversion_transformations field
        migrations.AddField(
            model_name='analysisjob',
            name='post_conversion_transformations',
            field=models.JSONField(
                blank=True,
                default=dict,
                help_text='Client-side transformations applied after image conversion (rotation, etc.)'
            ),
        ),
        # Add detected_animals field (list of all detected animals)
        migrations.AddField(
            model_name='analysisjob',
            name='detected_animals',
            field=models.JSONField(
                blank=True,
                default=list,
                help_text='List of all detected animals with metadata. Format: [{"scientific_name": str, "common_name": str, "confidence": float, "animal_id": uuid, "is_new": bool}, ...]'
            ),
        ),
        # Add selected_animal_index field
        migrations.AddField(
            model_name='analysisjob',
            name='selected_animal_index',
            field=models.IntegerField(
                blank=True,
                help_text='Index of the animal selected by user from detected_animals list',
                null=True
            ),
        ),
    ]
